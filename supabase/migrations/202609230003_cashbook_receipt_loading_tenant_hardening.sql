BEGIN;

/*
  CB-2D3: populate Cashbook tenant ownership only when the existing
  Payment Receipt / Loading Advance source synchronization runs.

  This migration intentionally performs no Cashbook data backfill and does
  not alter RLS, policies, existing table grants, or unrelated writers.
*/

DO $preflight$
DECLARE
  v_missing text;
BEGIN
  IF to_regclass('public.cashbook_entries') IS NULL
     OR to_regclass('public.payment_receipts') IS NULL
     OR to_regclass('public.loadings') IS NULL
     OR to_regclass('public.bookings') IS NULL
     OR to_regclass('public.addas') IS NULL THEN
    RAISE EXCEPTION 'CB-2D3 requires Cashbook, Payment Receipt, Loading, Booking, and Adda tables';
  END IF;

  IF to_regprocedure('public.ut_sync_payment_receipt_cashbook(text)') IS NULL
     OR to_regprocedure('public.ut_apply_payment_receipt_accounting()') IS NULL
     OR to_regprocedure('public.ut_sync_loading_advance_cashbook(text)') IS NULL
     OR to_regprocedure('public.ut_sync_loading_advance_trigger()') IS NULL
     OR to_regprocedure('public.ut_protect_automatic_cashbook_entries()') IS NULL THEN
    RAISE EXCEPTION 'CB-2D3 expected deployed Receipt/Loading routines or Cashbook guard are missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS a
    WHERE a.attrelid = 'public.cashbook_entries'::regclass
      AND a.attname = 'adda_id'
      AND a.atttypid = 'uuid'::regtype
      AND a.attnotnull = false
      AND a.attgenerated = ''
      AND a.atthasdef = false
      AND NOT a.attisdropped
  ) THEN
    RAISE EXCEPTION 'CB-2D3 requires nullable Cashbook adda_id without a default';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS c
    WHERE c.conrelid = 'public.cashbook_entries'::regclass
      AND c.conname = 'cashbook_entries_adda_id_fkey'
      AND c.contype = 'f'
      AND c.confrelid = 'public.addas'::regclass
      AND c.confdeltype = 'r'
      AND c.convalidated
  ) THEN
    RAISE EXCEPTION 'CB-2D3 requires the validated Cashbook adda_id -> addas(id) RESTRICT FK';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index AS i
    JOIN pg_catalog.pg_class AS idx ON idx.oid = i.indexrelid
    WHERE i.indrelid = 'public.cashbook_entries'::regclass
      AND idx.relname = 'cashbook_entries_adda_id_entry_date_idx'
      AND i.indisvalid AND i.indisready
      AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(adda_id, entry_date)%'
      AND pg_catalog.pg_get_expr(i.indpred, i.indrelid) ILIKE '%adda_id IS NOT NULL%'
  ) THEN
    RAISE EXCEPTION 'CB-2D3 requires the valid Stage A tenant/date Cashbook index';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index AS i
    JOIN pg_catalog.pg_class AS x ON x.oid = i.indexrelid
    WHERE i.indrelid = 'public.cashbook_entries'::regclass
      AND x.relname = 'cashbook_entries_automatic_reference_uidx'
      AND i.indisunique
      AND i.indisvalid
      AND i.indisready
      AND i.indnkeyatts = 2
      AND i.indnatts = 2
      AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%reference_type%reference_id%'
      AND pg_catalog.pg_get_expr(i.indpred, i.indrelid) ILIKE '%payment_receipt%'
      AND pg_catalog.pg_get_expr(i.indpred, i.indrelid) ILIKE '%loading_advance%'
      AND pg_catalog.pg_get_expr(i.indpred, i.indrelid) ILIKE '%reference_id IS NOT NULL%'
      AND position(' and ' IN lower(pg_catalog.pg_get_expr(i.indpred,i.indrelid))) > 0
      AND position(' and ' IN substring(lower(pg_catalog.pg_get_expr(i.indpred,i.indrelid))
        FROM position(' and ' IN lower(pg_catalog.pg_get_expr(i.indpred,i.indrelid))) + 5)) = 0
      AND position(' or ' IN lower(pg_catalog.pg_get_expr(i.indpred,i.indrelid))) = 0
  ) THEN
    RAISE EXCEPTION 'CB-2D3 requires the valid automatic Receipt/Loading unique reference index';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS t
    WHERE t.tgrelid = 'public.payment_receipts'::regclass
      AND t.tgname = 'payment_receipts_apply_cashbook_accounting'
      AND NOT t.tgisinternal
      AND t.tgenabled IN ('O','A')
      AND t.tgtype = 29
      AND t.tgqual IS NULL
      AND t.tgfoid = 'public.ut_apply_payment_receipt_accounting()'::regprocedure
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS t
    WHERE t.tgrelid = 'public.loadings'::regclass
      AND t.tgname = 'loadings_sync_advance_cashbook'
      AND NOT t.tgisinternal
      AND t.tgenabled IN ('O','A')
      AND t.tgtype = 29
      AND t.tgqual IS NULL
      AND t.tgfoid = 'public.ut_sync_loading_advance_trigger()'::regprocedure
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS t
    WHERE t.tgrelid = 'public.cashbook_entries'::regclass
      AND t.tgname = 'cashbook_entries_protect_automatic_sources'
      AND NOT t.tgisinternal
      AND t.tgenabled IN ('O','A')
      AND t.tgtype = 31
      AND t.tgqual IS NULL
      AND t.tgfoid = 'public.ut_protect_automatic_cashbook_entries()'::regprocedure
  ) THEN
    RAISE EXCEPTION 'CB-2D3 required Receipt/Loading source trigger or automatic Cashbook guard is missing/disabled';
  END IF;

  SELECT string_agg(required.column_name, ', ' ORDER BY required.column_name)
  INTO v_missing
  FROM (VALUES
    ('cashbook_entries', 'adda_id'),
    ('cashbook_entries', 'entry_date'),
    ('cashbook_entries', 'entry_type'),
    ('cashbook_entries', 'person_type'),
    ('cashbook_entries', 'person_name'),
    ('cashbook_entries', 'vehicle_id'),
    ('cashbook_entries', 'driver_id'),
    ('cashbook_entries', 'loading_id'),
    ('cashbook_entries', 'payment_method'),
    ('cashbook_entries', 'amount'),
    ('cashbook_entries', 'description'),
    ('cashbook_entries', 'reference_type'),
    ('cashbook_entries', 'reference_id'),
    ('payment_receipts', 'id'),
    ('payment_receipts', 'receipt_no'),
    ('payment_receipts', 'receipt_date'),
    ('payment_receipts', 'loading_id'),
    ('payment_receipts', 'amount'),
    ('payment_receipts', 'payment_method'),
    ('payment_receipts', 'remarks'),
    ('loadings', 'id'),
    ('loadings', 'loading_no'),
    ('loadings', 'loading_date'),
    ('loadings', 'booking_id'),
    ('loadings', 'vehicle_id'),
    ('loadings', 'driver_id'),
    ('loadings', 'advance_amount'),
    ('bookings', 'id'),
    ('bookings', 'adda_id'),
    ('bookings', 'party_id'),
    ('bookings', 'sender_name'),
    ('parties', 'id'),
    ('parties', 'adda_id'),
    ('parties', 'name')
  ) AS required(table_name, column_name)
  WHERE NOT EXISTS (
    SELECT 1
    FROM information_schema.columns AS c
    WHERE c.table_schema = 'public'
      AND c.table_name = required.table_name
      AND c.column_name = required.column_name
  );

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'CB-2D3 required source/Cashbook columns are missing: %', v_missing;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.cashbook_entries AS c
    WHERE c.reference_type IN ('payment_receipt', 'loading_advance')
      AND c.reference_id IS NOT NULL
    GROUP BY c.reference_type, c.reference_id
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'CB-2D3 found duplicate automatic Receipt/Loading Cashbook references';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.cashbook_entries AS c
    LEFT JOIN public.payment_receipts AS r
      ON c.reference_type = 'payment_receipt'
     AND r.id::text = c.reference_id
    LEFT JOIN public.loadings AS receipt_loading
      ON receipt_loading.id = r.loading_id
    LEFT JOIN public.bookings AS receipt_booking
      ON receipt_booking.id = receipt_loading.booking_id
    LEFT JOIN public.addas AS receipt_adda
      ON receipt_adda.id = receipt_booking.adda_id
    LEFT JOIN public.loadings AS advance_loading
      ON c.reference_type = 'loading_advance'
     AND advance_loading.id::text = c.reference_id
    LEFT JOIN public.bookings AS advance_booking
      ON advance_booking.id = advance_loading.booking_id
    LEFT JOIN public.addas AS advance_adda
      ON advance_adda.id = advance_booking.adda_id
    WHERE c.reference_type IN ('payment_receipt', 'loading_advance')
      AND c.reference_id IS NOT NULL
      AND (
        CASE c.reference_type
          WHEN 'payment_receipt' THEN receipt_booking.adda_id
          WHEN 'loading_advance' THEN advance_booking.adda_id
        END IS NULL
        OR (c.reference_type = 'payment_receipt' AND receipt_adda.id IS NULL)
        OR (c.reference_type = 'loading_advance' AND advance_adda.id IS NULL)
        OR (
          c.adda_id IS NOT NULL
          AND c.adda_id IS DISTINCT FROM CASE c.reference_type
            WHEN 'payment_receipt' THEN receipt_booking.adda_id
            WHEN 'loading_advance' THEN advance_booking.adda_id
          END
        )
      )
  ) THEN
    RAISE EXCEPTION 'CB-2D3 found a protected Cashbook row with missing source Adda or a conflicting non-NULL adda_id';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.loadings AS loading
    LEFT JOIN (
      SELECT receipt.loading_id, sum(receipt.amount) AS receipt_total
      FROM public.payment_receipts AS receipt
      GROUP BY receipt.loading_id
    ) AS receipts ON receipts.loading_id = loading.id
    WHERE coalesce(loading.advance_amount, 0) < coalesce(receipts.receipt_total, 0)
  ) THEN
    RAISE EXCEPTION 'CB-2D3 found Loading advance amounts below their Payment Receipt totals';
  END IF;

  IF position('Party Payment -' IN pg_catalog.pg_get_functiondef(
       'public.ut_sync_payment_receipt_cashbook(text)'::regprocedure)) = 0
     OR position('Payment Receipt belongs to another Adda' IN pg_catalog.pg_get_functiondef(
       'public.ut_apply_payment_receipt_accounting()'::regprocedure)) = 0
     OR position('Loading Advance -' IN pg_catalog.pg_get_functiondef(
       'public.ut_sync_loading_advance_cashbook(text)'::regprocedure)) = 0
     OR position('Loading belongs to another Adda' IN pg_catalog.pg_get_functiondef(
       'public.ut_sync_loading_advance_trigger()'::regprocedure)) = 0
     OR position('ut.cashbook_sync' IN pg_catalog.pg_get_functiondef(
       'public.ut_protect_automatic_cashbook_entries()'::regprocedure)) = 0 THEN
    RAISE EXCEPTION 'CB-2D3 deployed routine/guard definitions drift from the reviewed Receipt/Loading contract';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.payment_receipts AS r
    LEFT JOIN public.loadings AS l ON l.id = r.loading_id
    LEFT JOIN public.bookings AS b ON b.id = l.booking_id
    LEFT JOIN public.addas AS a ON a.id = b.adda_id
    WHERE b.adda_id IS NULL OR a.id IS NULL
  ) THEN
    RAISE EXCEPTION 'CB-2D3 found a Payment Receipt without authoritative Loading -> Booking Adda context';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.loadings AS l
    LEFT JOIN public.bookings AS b ON b.id = l.booking_id
    LEFT JOIN public.addas AS a ON a.id = b.adda_id
    LEFT JOIN (
      SELECT r.loading_id, sum(r.amount) AS receipt_total
      FROM public.payment_receipts AS r
      GROUP BY r.loading_id
    ) AS rt ON rt.loading_id = l.id
    WHERE (
      greatest(coalesce(l.advance_amount, 0) - coalesce(rt.receipt_total, 0), 0) > 0
      OR EXISTS (
        SELECT 1
        FROM public.cashbook_entries AS c
        WHERE c.reference_type = 'loading_advance'
          AND c.reference_id = l.id::text
      )
    )
      AND (b.adda_id IS NULL OR a.id IS NULL)
  ) THEN
    RAISE EXCEPTION 'CB-2D3 found a Loading Advance requiring Cashbook synchronization without authoritative Booking Adda context';
  END IF;
END
$preflight$;

CREATE OR REPLACE FUNCTION public.ut_cashbook_assert_source_adda_id(
  p_existing_adda_id uuid,
  p_authoritative_adda_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $function$
BEGIN
  IF p_authoritative_adda_id IS NULL THEN
    RAISE EXCEPTION USING
      errcode = '23503',
      message = 'Authoritative source Booking Adda is unavailable';
  END IF;

  IF p_existing_adda_id IS NOT NULL
     AND p_existing_adda_id IS DISTINCT FROM p_authoritative_adda_id THEN
    RAISE EXCEPTION USING
      errcode = '23514',
      message = 'Cashbook Adda conflicts with authoritative source Booking Adda';
  END IF;

  RETURN coalesce(p_existing_adda_id, p_authoritative_adda_id);
END
$function$;

REVOKE ALL ON FUNCTION public.ut_cashbook_assert_source_adda_id(uuid,uuid)
  FROM PUBLIC, anon, authenticated, service_role;

DO $grant_private_assertion$
DECLARE
  v_owner name;
BEGIN
  FOR v_owner IN
    SELECT DISTINCT owner_role.rolname
    FROM pg_catalog.pg_proc AS p
    JOIN pg_catalog.pg_roles AS owner_role ON owner_role.oid = p.proowner
    WHERE p.oid IN (
      'public.ut_sync_payment_receipt_cashbook(text)'::regprocedure,
      'public.ut_apply_payment_receipt_accounting()'::regprocedure,
      'public.ut_sync_loading_advance_cashbook(text)'::regprocedure,
      'public.ut_sync_loading_advance_trigger()'::regprocedure
    )
  LOOP
    IF v_owner::text IN ('anon','authenticated','service_role') THEN
      RAISE EXCEPTION 'CB-2D3 source sync functions have an unsafe owner role: %', v_owner;
    END IF;

    EXECUTE pg_catalog.format(
      'GRANT EXECUTE ON FUNCTION public.ut_cashbook_assert_source_adda_id(uuid,uuid) TO %I',
      v_owner
    );
  END LOOP;
END
$grant_private_assertion$;

CREATE OR REPLACE FUNCTION public.ut_capture_loading_cashbook_delete_context()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_source_adda_id uuid;
  v_context_key text;
BEGIN
  SELECT booking.adda_id
  INTO v_source_adda_id
  FROM public.bookings AS booking
  WHERE booking.id = OLD.booking_id;

  v_context_key :=
    'ut.cashbook_loading_delete.' || pg_catalog.md5(OLD.id::text);

  /*
    A transaction-local snapshot preserves the authoritative Loading ->
    Booking Adda for receipt child DELETE triggers in an ON DELETE CASCADE.
    It performs no row write; the value disappears at transaction end.
  */
  PERFORM pg_catalog.set_config(
    v_context_key,
    coalesce(v_source_adda_id::text, ''),
    true
  );

  RETURN OLD;
END
$function$;

REVOKE ALL ON FUNCTION public.ut_capture_loading_cashbook_delete_context()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ut_sync_loading_advance_cashbook(
  p_loading_id text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  loading_record record;
  receipt_total numeric := 0;
  original_advance numeric := 0;
  existing_adda_id uuid;
  delete_context_adda_id uuid;
  loading_delete_context_key text;
BEGIN
  PERFORM pg_catalog.set_config('ut.cashbook_sync', 'on', true);

  SELECT
    loading.id,
    loading.loading_no,
    loading.loading_date,
    loading.vehicle_id,
    loading.driver_id,
    loading.advance_amount,
    booking.id AS booking_id,
    booking.adda_id,
    booking.sender_name,
    party.name AS party_name
  INTO loading_record
  FROM public.loadings AS loading
  JOIN public.bookings AS booking
    ON booking.id = loading.booking_id
  LEFT JOIN public.parties AS party
    ON party.id = booking.party_id
   AND party.adda_id = booking.adda_id
  WHERE loading.id::text = p_loading_id;

  IF NOT FOUND THEN
    SELECT cashbook.adda_id
    INTO existing_adda_id
    FROM public.cashbook_entries AS cashbook
    WHERE cashbook.reference_type = 'loading_advance'
      AND cashbook.reference_id = p_loading_id
    FOR UPDATE;

    IF FOUND THEN
      loading_delete_context_key :=
        'ut.cashbook_loading_delete.' || pg_catalog.md5(p_loading_id);
      delete_context_adda_id := nullif(
        pg_catalog.current_setting(loading_delete_context_key, true),
        ''
      )::uuid;

      IF delete_context_adda_id IS NOT NULL THEN
        PERFORM public.ut_cashbook_assert_source_adda_id(
          existing_adda_id,
          delete_context_adda_id
        );
      END IF;

      -- Missing-source cleanup preserves the legacy exact-reference delete.
      -- Validate against a captured authoritative tenant when one is available.
      DELETE FROM public.cashbook_entries AS cashbook
      WHERE cashbook.reference_type = 'loading_advance'
        AND cashbook.reference_id = p_loading_id;
    END IF;

    RETURN;
  END IF;

  SELECT coalesce(sum(receipt.amount), 0)
  INTO receipt_total
  FROM public.payment_receipts AS receipt
  WHERE receipt.loading_id = loading_record.id;

  IF coalesce(loading_record.advance_amount, 0) < receipt_total THEN
    RAISE EXCEPTION USING
      errcode = '23514',
      message = 'Loading received amount cannot be below its Payment Receipt total';
  END IF;

  original_advance :=
    coalesce(loading_record.advance_amount, 0) - receipt_total;

  IF original_advance <= 0 THEN
    SELECT cashbook.adda_id
    INTO existing_adda_id
    FROM public.cashbook_entries AS cashbook
    WHERE cashbook.reference_type = 'loading_advance'
      AND cashbook.reference_id = loading_record.id::text
    FOR UPDATE;

    IF FOUND THEN
      IF loading_record.adda_id IS NOT NULL THEN
        PERFORM public.ut_cashbook_assert_source_adda_id(
          existing_adda_id,
          loading_record.adda_id
        );
      END IF;

      DELETE FROM public.cashbook_entries AS cashbook
      WHERE cashbook.reference_type = 'loading_advance'
        AND cashbook.reference_id = loading_record.id::text;
    END IF;

    RETURN;
  END IF;

  IF loading_record.adda_id IS NULL THEN
    RAISE EXCEPTION USING
      errcode = '23503',
      message = 'Loading Booking Adda is unavailable; refusing to write its Cashbook entry';
  END IF;

  SELECT cashbook.adda_id
  INTO existing_adda_id
  FROM public.cashbook_entries AS cashbook
  WHERE cashbook.reference_type = 'loading_advance'
    AND cashbook.reference_id = loading_record.id::text
  FOR UPDATE;

  IF FOUND
     AND existing_adda_id IS NOT NULL
     AND existing_adda_id IS DISTINCT FROM loading_record.adda_id THEN
    RAISE EXCEPTION USING
      errcode = '23514',
      message = 'Cashbook Adda conflicts with authoritative Loading Booking Adda';
  END IF;

  UPDATE public.cashbook_entries AS cashbook
  SET
    adda_id = public.ut_cashbook_assert_source_adda_id(cashbook.adda_id, loading_record.adda_id),
    entry_date = loading_record.loading_date,
    entry_type = 'Cash In',
    person_type = 'Customer',
    person_name = coalesce(
      nullif(btrim(loading_record.party_name), ''),
      nullif(btrim(loading_record.sender_name), ''),
      'Party'
    ),
    vehicle_id = loading_record.vehicle_id,
    driver_id = loading_record.driver_id,
    loading_id = loading_record.id,
    payment_method = 'Cash',
    amount = original_advance,
    description = 'Loading Advance - ' || coalesce(
      nullif(btrim(loading_record.loading_no), ''),
      loading_record.id::text
    ),
    reference_type = 'loading_advance',
    reference_id = loading_record.id::text
  WHERE cashbook.reference_type = 'loading_advance'
    AND cashbook.reference_id = loading_record.id::text;

  IF FOUND THEN
    RETURN;
  END IF;

  INSERT INTO public.cashbook_entries (
    adda_id,
    entry_date,
    entry_type,
    person_type,
    person_name,
    vehicle_id,
    driver_id,
    loading_id,
    payment_method,
    amount,
    description,
    reference_type,
    reference_id
  )
  VALUES (
    loading_record.adda_id,
    loading_record.loading_date,
    'Cash In',
    'Customer',
    coalesce(
      nullif(btrim(loading_record.party_name), ''),
      nullif(btrim(loading_record.sender_name), ''),
      'Party'
    ),
    loading_record.vehicle_id,
    loading_record.driver_id,
    loading_record.id,
    'Cash',
    original_advance,
    'Loading Advance - ' || coalesce(
      nullif(btrim(loading_record.loading_no), ''),
      loading_record.id::text
    ),
    'loading_advance',
    loading_record.id::text
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.ut_sync_payment_receipt_cashbook(
  p_receipt_id text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  receipt_record record;
  existing_adda_id uuid;
  delete_context_loading_id text;
  delete_context_adda_id uuid;
  loading_delete_context_key text;
BEGIN
  PERFORM pg_catalog.set_config('ut.cashbook_sync', 'on', true);

  SELECT
    receipt.id,
    receipt.receipt_no,
    receipt.receipt_date,
    receipt.loading_id,
    receipt.amount,
    receipt.payment_method,
    receipt.remarks,
    loading.loading_no,
    loading.vehicle_id,
    loading.driver_id,
    booking.adda_id,
    booking.sender_name,
    party.name AS party_name
  INTO receipt_record
  FROM public.payment_receipts AS receipt
  JOIN public.loadings AS loading
    ON loading.id = receipt.loading_id
  JOIN public.bookings AS booking
    ON booking.id = loading.booking_id
  LEFT JOIN public.parties AS party
    ON party.id = booking.party_id
   AND party.adda_id = booking.adda_id
  WHERE receipt.id::text = p_receipt_id;

  IF NOT FOUND THEN
    SELECT
      cashbook.adda_id,
      cashbook.loading_id::text
    INTO
      existing_adda_id,
      delete_context_loading_id
    FROM public.cashbook_entries AS cashbook
    WHERE cashbook.reference_type = 'payment_receipt'
      AND cashbook.reference_id = p_receipt_id
    FOR UPDATE;

    IF FOUND THEN
      IF delete_context_loading_id IS NOT NULL THEN
        loading_delete_context_key :=
          'ut.cashbook_loading_delete.' || pg_catalog.md5(delete_context_loading_id);
        delete_context_adda_id := nullif(
          pg_catalog.current_setting(loading_delete_context_key, true),
          ''
        )::uuid;
      END IF;

      IF delete_context_adda_id IS NOT NULL THEN
        PERFORM public.ut_cashbook_assert_source_adda_id(
          existing_adda_id,
          delete_context_adda_id
        );
      END IF;

      -- Without the deleted source or a captured Loading tenant, preserve
      -- legacy exact-reference cleanup without inventing a tenant value.
      DELETE FROM public.cashbook_entries AS cashbook
      WHERE cashbook.reference_type = 'payment_receipt'
        AND cashbook.reference_id = p_receipt_id;
    END IF;

    RETURN;
  END IF;

  IF receipt_record.amount IS NULL OR receipt_record.amount <= 0 THEN
    RAISE EXCEPTION USING
      errcode = '23514',
      message = 'Payment Receipt amount must be greater than zero';
  END IF;

  IF receipt_record.adda_id IS NULL THEN
    RAISE EXCEPTION USING
      errcode = '23503',
      message = 'Payment Receipt Booking Adda is unavailable';
  END IF;

  SELECT cashbook.adda_id
  INTO existing_adda_id
  FROM public.cashbook_entries AS cashbook
  WHERE cashbook.reference_type = 'payment_receipt'
    AND cashbook.reference_id = receipt_record.id::text
  FOR UPDATE;

  IF FOUND
     AND existing_adda_id IS NOT NULL
     AND existing_adda_id IS DISTINCT FROM receipt_record.adda_id THEN
    RAISE EXCEPTION USING
      errcode = '23514',
      message = 'Cashbook Adda conflicts with authoritative Payment Receipt Booking Adda';
  END IF;

  UPDATE public.cashbook_entries AS cashbook
  SET
    adda_id = public.ut_cashbook_assert_source_adda_id(cashbook.adda_id, receipt_record.adda_id),
    entry_date = receipt_record.receipt_date,
    entry_type = 'Cash In',
    person_type = 'Customer',
    person_name = coalesce(
      nullif(btrim(receipt_record.party_name), ''),
      nullif(btrim(receipt_record.sender_name), ''),
      'Party'
    ),
    vehicle_id = receipt_record.vehicle_id,
    driver_id = receipt_record.driver_id,
    loading_id = receipt_record.loading_id,
    payment_method = receipt_record.payment_method,
    amount = receipt_record.amount,
    description = 'Party Payment - ' || coalesce(
      nullif(btrim(receipt_record.receipt_no), ''),
      receipt_record.id::text
    ),
    reference_type = 'payment_receipt',
    reference_id = receipt_record.id::text
  WHERE cashbook.reference_type = 'payment_receipt'
    AND cashbook.reference_id = receipt_record.id::text;

  IF FOUND THEN
    RETURN;
  END IF;

  INSERT INTO public.cashbook_entries (
    adda_id,
    entry_date,
    entry_type,
    person_type,
    person_name,
    vehicle_id,
    driver_id,
    loading_id,
    payment_method,
    amount,
    description,
    reference_type,
    reference_id
  )
  VALUES (
    receipt_record.adda_id,
    receipt_record.receipt_date,
    'Cash In',
    'Customer',
    coalesce(
      nullif(btrim(receipt_record.party_name), ''),
      nullif(btrim(receipt_record.sender_name), ''),
      'Party'
    ),
    receipt_record.vehicle_id,
    receipt_record.driver_id,
    receipt_record.loading_id,
    receipt_record.payment_method,
    receipt_record.amount,
    'Party Payment - ' || coalesce(
      nullif(btrim(receipt_record.receipt_no), ''),
      receipt_record.id::text
    ),
    'payment_receipt',
    receipt_record.id::text
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.ut_apply_payment_receipt_accounting()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  amount_delta numeric;
  source_adda_id uuid;
  updated_loading_id text;
  existing_cashbook_adda_id uuid;
  loading_delete_context_key text;
BEGIN
  IF tg_op = 'UPDATE'
    AND new.loading_id IS DISTINCT FROM old.loading_id
  THEN
    RAISE EXCEPTION USING
      errcode = '23514',
      message = 'A Payment Receipt cannot be moved to another Loading';
  END IF;

  IF tg_op IN ('INSERT', 'UPDATE') THEN
    IF new.amount IS NULL OR new.amount <= 0 THEN
      RAISE EXCEPTION USING
        errcode = '23514',
        message = 'Payment Receipt amount must be greater than zero';
    END IF;

    amount_delta := CASE
      WHEN tg_op = 'INSERT' THEN new.amount
      ELSE new.amount - old.amount
    END;

    SELECT booking.adda_id
    INTO source_adda_id
    FROM public.loadings AS loading
    JOIN public.bookings AS booking
      ON booking.id = loading.booking_id
    WHERE loading.id = new.loading_id;

    IF source_adda_id IS NULL THEN
      RAISE EXCEPTION USING
        errcode = '23503',
        message = 'Payment Receipt Loading is unavailable';
    END IF;

    IF auth.uid() IS NOT NULL
      AND NOT public.is_super_admin()
      AND source_adda_id IS DISTINCT FROM
        public.current_user_adda_id()
    THEN
      RAISE EXCEPTION USING
        errcode = '42501',
        message = 'Payment Receipt belongs to another Adda';
    END IF;

    UPDATE public.loadings AS loading
    SET
      advance_amount =
        coalesce(loading.advance_amount, 0) + amount_delta,
      remaining_amount = greatest(
        coalesce(booking.freight, 0) -
          (coalesce(loading.advance_amount, 0) + amount_delta),
        0
      ),
      payment_status = CASE
        WHEN coalesce(loading.advance_amount, 0) + amount_delta <= 0
          THEN 'Unpaid'
        WHEN coalesce(loading.advance_amount, 0) + amount_delta
          >= coalesce(booking.freight, 0)
          THEN 'Paid'
        ELSE 'Partial'
      END
    FROM public.bookings AS booking
    WHERE loading.id = new.loading_id
      AND booking.id = loading.booking_id
    RETURNING loading.id::text INTO updated_loading_id;

    IF updated_loading_id IS NULL THEN
      RAISE EXCEPTION USING
        errcode = '23503',
        message = 'Payment Receipt Loading is unavailable';
    END IF;

    PERFORM public.ut_sync_payment_receipt_cashbook(new.id::text);
    RETURN new;
  END IF;

  UPDATE public.loadings AS loading
  SET
    advance_amount = greatest(
      coalesce(loading.advance_amount, 0) - old.amount,
      0
    ),
    remaining_amount = greatest(
      coalesce(booking.freight, 0) - greatest(
        coalesce(loading.advance_amount, 0) - old.amount,
        0
      ),
      0
    ),
    payment_status = CASE
      WHEN greatest(
        coalesce(loading.advance_amount, 0) - old.amount,
        0
      ) <= 0 THEN 'Unpaid'
      WHEN greatest(
        coalesce(loading.advance_amount, 0) - old.amount,
        0
      ) >= coalesce(booking.freight, 0) THEN 'Paid'
      ELSE 'Partial'
    END
  FROM public.bookings AS booking
  WHERE loading.id = old.loading_id
    AND booking.id = loading.booking_id;

  SELECT booking.adda_id
  INTO source_adda_id
  FROM public.loadings AS loading
  JOIN public.bookings AS booking
    ON booking.id = loading.booking_id
  WHERE loading.id = old.loading_id;

  IF source_adda_id IS NULL THEN
    loading_delete_context_key :=
      'ut.cashbook_loading_delete.' || pg_catalog.md5(old.loading_id::text);
    source_adda_id := nullif(
      pg_catalog.current_setting(loading_delete_context_key, true),
      ''
    )::uuid;
  END IF;

  PERFORM pg_catalog.set_config('ut.cashbook_sync', 'on', true);

  SELECT cashbook.adda_id
  INTO existing_cashbook_adda_id
  FROM public.cashbook_entries AS cashbook
  WHERE cashbook.reference_type = 'payment_receipt'
    AND cashbook.reference_id = old.id::text
  FOR UPDATE;

  IF FOUND THEN
    IF source_adda_id IS NOT NULL THEN
      PERFORM public.ut_cashbook_assert_source_adda_id(
        existing_cashbook_adda_id,
        source_adda_id
      );
    END IF;

    DELETE FROM public.cashbook_entries AS cashbook
    WHERE cashbook.reference_type = 'payment_receipt'
      AND cashbook.reference_id = old.id::text;
  END IF;

  RETURN old;
END
$function$;

CREATE OR REPLACE FUNCTION public.ut_sync_loading_advance_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  source_adda_id uuid;
  source_booking_id uuid;
  existing_cashbook_adda_id uuid;
  loading_delete_context_key text;
BEGIN
  source_booking_id := CASE
    WHEN tg_op = 'DELETE' THEN old.booking_id
    ELSE new.booking_id
  END;

  SELECT booking.adda_id
  INTO source_adda_id
  FROM public.bookings AS booking
  WHERE booking.id = source_booking_id;

  IF source_adda_id IS NULL AND tg_op = 'DELETE' THEN
    loading_delete_context_key :=
      'ut.cashbook_loading_delete.' || pg_catalog.md5(old.id::text);
    source_adda_id := nullif(
      pg_catalog.current_setting(loading_delete_context_key, true),
      ''
    )::uuid;
  END IF;

  IF source_adda_id IS NULL AND tg_op <> 'DELETE' THEN
    RAISE EXCEPTION USING
      errcode = '23503',
      message = 'Loading Booking is unavailable';
  END IF;

  IF source_adda_id IS NOT NULL
    AND auth.uid() IS NOT NULL
    AND NOT public.is_super_admin()
    AND source_adda_id IS DISTINCT FROM
      public.current_user_adda_id()
  THEN
    RAISE EXCEPTION USING
      errcode = '42501',
      message = 'Loading belongs to another Adda';
  END IF;

  IF tg_op = 'DELETE' THEN
    PERFORM pg_catalog.set_config('ut.cashbook_sync', 'on', true);

    SELECT cashbook.adda_id
    INTO existing_cashbook_adda_id
    FROM public.cashbook_entries AS cashbook
    WHERE cashbook.reference_type = 'loading_advance'
      AND cashbook.reference_id = old.id::text
    FOR UPDATE;

    IF FOUND THEN
      IF source_adda_id IS NOT NULL THEN
        PERFORM public.ut_cashbook_assert_source_adda_id(
          existing_cashbook_adda_id,
          source_adda_id
        );
      END IF;

      DELETE FROM public.cashbook_entries AS cashbook
      WHERE cashbook.reference_type = 'loading_advance'
        AND cashbook.reference_id = old.id::text;
    END IF;

    RETURN old;
  END IF;

  PERFORM public.ut_sync_loading_advance_cashbook(new.id::text);
  RETURN new;
END
$function$;

DO $install_context_trigger$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS t
    WHERE t.tgrelid = 'public.loadings'::regclass
      AND t.tgname = 'loadings_capture_cashbook_tenant_before_delete'
      AND NOT t.tgisinternal
      AND (
        t.tgfoid <> 'public.ut_capture_loading_cashbook_delete_context()'::regprocedure
        OR t.tgtype <> 11
        OR t.tgqual IS NOT NULL
        OR t.tgenabled NOT IN ('O','A')
      )
  ) THEN
    RAISE EXCEPTION 'The Loading DELETE context trigger name is already used by an incompatible trigger';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS t
    WHERE t.tgrelid = 'public.loadings'::regclass
      AND t.tgname = 'loadings_capture_cashbook_tenant_before_delete'
      AND NOT t.tgisinternal
  ) THEN
    CREATE TRIGGER loadings_capture_cashbook_tenant_before_delete
      BEFORE DELETE ON public.loadings
      FOR EACH ROW
      EXECUTE FUNCTION public.ut_capture_loading_cashbook_delete_context();
  END IF;
END
$install_context_trigger$;

COMMIT;
