BEGIN;

-- Phase 5B is append-only and prospective. It extends the shared commission
-- event lineage; it does not rewrite existing Phase 5 events or projections.
DO $phase5b_precondition$
BEGIN
  IF pg_catalog.to_regclass('public.adda_vehicle_commission_events') IS NULL
     OR pg_catalog.to_regclass('public.owner_gari_account_transactions') IS NULL
     OR pg_catalog.to_regclass('public.adda_account_entries') IS NULL
     OR pg_catalog.to_regclass('public.adda_expense_categories') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_other_adda_authorize(uuid,boolean)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_resolve_adda_accounting_tenant(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v2(uuid,date,date,date,text,uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'VEHICLE_COMMISSION_PHASE5B: Phase 5 contracts are missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index AS index_row
    WHERE index_row.indexrelid='public.adda_vehicle_commission_events_request_uidx'::pg_catalog.regclass
      AND index_row.indisunique AND index_row.indisvalid
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index AS index_row
    WHERE index_row.indexrelid='public.adda_vehicle_commission_events_one_reversal_uidx'::pg_catalog.regclass
      AND index_row.indisunique AND index_row.indisvalid
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index AS index_row
    WHERE index_row.indexrelid='public.owner_gari_transactions_commission_source_uidx'::pg_catalog.regclass
      AND index_row.indisunique AND index_row.indisvalid
  ) THEN
    RAISE EXCEPTION 'VEHICLE_COMMISSION_PHASE5B: required Phase 5 exact-once indexes are missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid='public.adda_vehicle_commission_events'::pg_catalog.regclass
      AND constraint_row.conname='adda_vehicle_commission_events_event_type_check'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid='public.adda_vehicle_commission_events'::pg_catalog.regclass
      AND constraint_row.conname='adda_vehicle_commission_events_event_shape_check'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid='public.adda_vehicle_commission_events'::pg_catalog.regclass
      AND constraint_row.conname='adda_vehicle_commission_events_reversal_metadata_check'
  ) THEN
    RAISE EXCEPTION 'VEHICLE_COMMISSION_PHASE5B: expected Phase 5 event constraints are missing';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute AS attribute
    WHERE attribute.attrelid='public.adda_vehicle_commission_events'::pg_catalog.regclass
      AND attribute.attname IN('parent_event_id','root_event_id','correction_reason')
      AND attribute.attnum>0 AND NOT attribute.attisdropped
  ) THEN
    RAISE EXCEPTION 'VEHICLE_COMMISSION_PHASE5B: lineage columns already exist';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS routine
    JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=routine.pronamespace
    WHERE namespace.nspname='public' AND routine.proname IN(
      'reissue_adda_vehicle_commission','adjust_adda_vehicle_commission',
      'reverse_adda_vehicle_commission_correction','get_adda_vehicle_commission_history_v2',
      'get_owner_gari_account_statement_v3','ut_adda_vehicle_commission_root_id',
      'ut_adda_vehicle_commission_event_effect','ut_adda_vehicle_commission_effective_root',
      'ut_project_adda_vehicle_commission_event'
    )
  ) THEN
    RAISE EXCEPTION 'VEHICLE_COMMISSION_PHASE5B: a proposed routine name is already occupied';
  END IF;
END;
$phase5b_precondition$;

ALTER TABLE public.adda_vehicle_commission_events
  ADD COLUMN parent_event_id uuid NULL,
  ADD COLUMN root_event_id uuid NULL,
  ADD COLUMN correction_reason text NULL;

ALTER TABLE public.adda_vehicle_commission_events
  ADD CONSTRAINT adda_vehicle_commission_events_parent_adda_vehicle_fkey
    FOREIGN KEY(parent_event_id,adda_id,vehicle_id)
    REFERENCES public.adda_vehicle_commission_events(id,adda_id,vehicle_id) ON DELETE RESTRICT,
  ADD CONSTRAINT adda_vehicle_commission_events_root_adda_vehicle_fkey
    FOREIGN KEY(root_event_id,adda_id,vehicle_id)
    REFERENCES public.adda_vehicle_commission_events(id,adda_id,vehicle_id) ON DELETE RESTRICT,
  DROP CONSTRAINT adda_vehicle_commission_events_event_type_check,
  ADD CONSTRAINT adda_vehicle_commission_events_event_type_check
    CHECK(event_type IN('commission','reversal','reissue','adjustment_increase','adjustment_decrease')),
  DROP CONSTRAINT adda_vehicle_commission_events_event_shape_check,
  ADD CONSTRAINT adda_vehicle_commission_events_event_shape_check CHECK(
    (event_type='commission' AND reverses_event_id IS NULL
      AND parent_event_id IS NULL AND root_event_id IS NULL AND correction_reason IS NULL)
    OR (event_type='reversal' AND reverses_event_id IS NOT NULL
      AND reverses_event_id<>id
      AND ((parent_event_id IS NULL AND root_event_id IS NULL)
        OR (parent_event_id IS NOT NULL AND parent_event_id<>id
          AND root_event_id IS NOT NULL AND root_event_id<>id))
      AND correction_reason IS NULL)
    OR (event_type IN('reissue','adjustment_increase','adjustment_decrease')
      AND reverses_event_id IS NULL AND parent_event_id IS NOT NULL AND parent_event_id<>id
      AND root_event_id IS NOT NULL AND root_event_id<>id
      AND NULLIF(pg_catalog.btrim(correction_reason),'') IS NOT NULL
      AND pg_catalog.length(correction_reason)<=500)
  ),
  DROP CONSTRAINT adda_vehicle_commission_events_reversal_metadata_check,
  ADD CONSTRAINT adda_vehicle_commission_events_reversal_metadata_check CHECK(
    (event_type='commission' AND reversal_date IS NULL AND reversal_reason IS NULL)
    OR (event_type='reversal' AND reversal_date IS NOT NULL
      AND NULLIF(pg_catalog.btrim(reversal_reason),'') IS NOT NULL)
    OR (event_type IN('reissue','adjustment_increase','adjustment_decrease')
      AND reversal_date IS NULL AND reversal_reason IS NULL)
  );

CREATE UNIQUE INDEX adda_vehicle_commission_events_one_reissue_per_reversal_uidx
  ON public.adda_vehicle_commission_events(parent_event_id)
  WHERE event_type='reissue';
CREATE INDEX adda_vehicle_commission_events_root_history_idx
  ON public.adda_vehicle_commission_events(adda_id,root_event_id,created_at,id)
  WHERE root_event_id IS NOT NULL;

ALTER TABLE public.owner_gari_account_transactions
  DROP CONSTRAINT owner_gari_transactions_type_check,
  DROP CONSTRAINT owner_gari_transactions_commission_source_check,
  DROP CONSTRAINT owner_gari_transactions_commission_amount_check;

ALTER TABLE public.owner_gari_account_transactions
  ADD CONSTRAINT owner_gari_transactions_type_check CHECK(transaction_type IN(
    'opening_seed','chakkar_net_credit','owner_withdrawal','gari_withdrawal',
    'monthly_adda_commission','monthly_adda_commission_reversal',
    'monthly_adda_commission_reissue','monthly_adda_commission_adjustment_increase',
    'monthly_adda_commission_adjustment_decrease',
    'monthly_adda_commission_correction_reversal_credit',
    'monthly_adda_commission_correction_reversal_debit',
    'adjustment_credit','adjustment_debit','voucher_adjustment_expense'
  )),
  ADD CONSTRAINT owner_gari_transactions_commission_source_check CHECK(
    (transaction_type='chakkar_net_credit'
      AND source_settlement_id IS NOT NULL AND source_adjustment_id IS NULL
      AND source_commission_event_id IS NULL)
    OR (transaction_type='voucher_adjustment_expense'
      AND source_settlement_id IS NULL AND source_adjustment_id IS NOT NULL
      AND source_commission_event_id IS NULL)
    OR (transaction_type IN(
      'monthly_adda_commission','monthly_adda_commission_reversal',
      'monthly_adda_commission_reissue','monthly_adda_commission_adjustment_increase',
      'monthly_adda_commission_adjustment_decrease',
      'monthly_adda_commission_correction_reversal_credit',
      'monthly_adda_commission_correction_reversal_debit'
    ) AND source_settlement_id IS NULL AND source_adjustment_id IS NULL
      AND source_commission_event_id IS NOT NULL)
    OR (transaction_type NOT IN(
      'chakkar_net_credit','voucher_adjustment_expense',
      'monthly_adda_commission','monthly_adda_commission_reversal',
      'monthly_adda_commission_reissue','monthly_adda_commission_adjustment_increase',
      'monthly_adda_commission_adjustment_decrease',
      'monthly_adda_commission_correction_reversal_credit',
      'monthly_adda_commission_correction_reversal_debit'
    ) AND source_settlement_id IS NULL AND source_adjustment_id IS NULL
      AND source_commission_event_id IS NULL)
  ),
  ADD CONSTRAINT owner_gari_transactions_commission_amount_check CHECK(
    (transaction_type NOT IN(
      'monthly_adda_commission','monthly_adda_commission_reissue',
      'monthly_adda_commission_adjustment_increase',
      'monthly_adda_commission_correction_reversal_debit'
    ) OR (amount<0 AND amount::text NOT IN('NaN','Infinity','-Infinity')))
    AND (transaction_type NOT IN(
      'monthly_adda_commission_reversal','monthly_adda_commission_adjustment_decrease',
      'monthly_adda_commission_correction_reversal_credit'
    ) OR (amount>0 AND amount::text NOT IN('NaN','Infinity','-Infinity')))
  );

CREATE OR REPLACE FUNCTION public.guard_adda_account_entries_append_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_original public.adda_account_entries%ROWTYPE;
  v_category_code text;
  v_category_policy text;
  v_entry_kind text;
BEGIN
  IF TG_OP='TRUNCATE' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_ACCOUNT_ENTRIES_APPEND_ONLY';
  END IF;
  IF TG_OP<>'INSERT' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_ACCOUNT_ENTRIES_APPEND_ONLY';
  END IF;
  IF coalesce(pg_catalog.current_setting('ut.adda_finance_rpc',true),'')<>'on' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_ACCOUNT_ENTRY_REQUIRES_PROTECTED_RPC';
  END IF;
  IF NEW.reverses_entry_id IS NOT NULL THEN
    SELECT original.* INTO v_original
    FROM public.adda_account_entries AS original
    WHERE original.adda_id=NEW.adda_id AND original.id=NEW.reverses_entry_id
    FOR KEY SHARE;
    IF NOT FOUND OR v_original.reverses_entry_id IS NOT NULL
       OR NEW.entry_kind=v_original.entry_kind
       OR NEW.amount IS DISTINCT FROM v_original.amount
       OR NEW.source_type IS DISTINCT FROM v_original.source_type
       OR NEW.source_id IS DISTINCT FROM v_original.source_id
       OR NEW.category_id IS DISTINCT FROM v_original.category_id
       OR NEW.booking_id IS DISTINCT FROM v_original.booking_id
       OR NEW.loading_id IS DISTINCT FROM v_original.loading_id
       OR NEW.vehicle_id IS DISTINCT FROM v_original.vehicle_id
       OR NEW.employee_id IS DISTINCT FROM v_original.employee_id
       OR NEW.salary_record_id IS DISTINCT FROM v_original.salary_record_id
       OR NEW.entry_date<v_original.entry_date THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='INVALID_ADDA_ACCOUNT_ENTRY_REVERSAL';
    END IF;
    v_entry_kind:=v_original.entry_kind;
  ELSE
    v_entry_kind:=NEW.entry_kind;
  END IF;
  IF NEW.source_type IN(
    'manual_adda_expense','employee_salary_generated','bilty_loss','bilty_margin',
    'vehicle_monthly_commission'
  ) AND NEW.category_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ADDA_EXPENSE_CATEGORY_REQUIRED';
  END IF;
  IF NEW.category_id IS NOT NULL THEN
    SELECT category.category_code,category.source_policy
      INTO v_category_code,v_category_policy
    FROM public.adda_expense_categories AS category
    WHERE category.adda_id=NEW.adda_id AND category.id=NEW.category_id
    FOR SHARE;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='ADDA_FINANCE_CATEGORY_TENANT_MISMATCH';
    END IF;
    IF NEW.reverses_entry_id IS NULL AND NOT EXISTS(
      SELECT 1 FROM public.adda_expense_categories AS active_category
      WHERE active_category.adda_id=NEW.adda_id AND active_category.id=NEW.category_id
        AND active_category.is_active
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ADDA_FINANCE_CATEGORY_INACTIVE';
    END IF;
    IF v_category_policy='manual' THEN
      IF NEW.source_type<>'manual_adda_expense' OR v_entry_kind<>'expense' THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='SYSTEM_SOURCE_REQUIRED_FOR_CATEGORY';
      END IF;
    ELSIF NOT(
      (v_category_code='employee_salary' AND NEW.source_type='employee_salary_generated' AND v_entry_kind='expense')
      OR (v_category_code='bilty_loss' AND NEW.source_type='bilty_loss' AND v_entry_kind='expense')
      OR (v_category_code='bilty_margin' AND NEW.source_type='bilty_margin' AND v_entry_kind='income')
      OR (v_category_code='vehicle_monthly_commission'
        AND NEW.source_type='vehicle_monthly_commission' AND v_entry_kind='income')
      OR (v_category_code='vehicle_monthly_commission_adjustment'
        AND NEW.source_type='vehicle_monthly_commission' AND v_entry_kind='expense')
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ADDA_FINANCE_SYSTEM_CATEGORY_SOURCE_MISMATCH';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ut_guard_owner_gari_commission_append_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_event public.adda_vehicle_commission_events%ROWTYPE;
  v_target public.adda_vehicle_commission_events%ROWTYPE;
  v_expected_type text;
  v_expected_amount numeric;
  v_expected_date date;
  v_is_commission boolean;
BEGIN
  IF TG_OP='TRUNCATE' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='OWNER_GARI_COMMISSION_PROJECTION_APPEND_ONLY';
  END IF;
  IF TG_OP='INSERT' AND NEW.transaction_type IN(
    'monthly_adda_commission','monthly_adda_commission_reversal',
    'monthly_adda_commission_reissue','monthly_adda_commission_adjustment_increase',
    'monthly_adda_commission_adjustment_decrease',
    'monthly_adda_commission_correction_reversal_credit',
    'monthly_adda_commission_correction_reversal_debit'
  ) THEN
    SELECT event.* INTO v_event
    FROM public.adda_vehicle_commission_events AS event
    WHERE event.id=NEW.source_commission_event_id
      AND event.adda_id=NEW.adda_id AND event.vehicle_id=NEW.vehicle_id
    FOR KEY SHARE;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='OWNER_GARI_COMMISSION_SOURCE_PROJECTION_MISMATCH';
    END IF;
    IF v_event.event_type='reversal' THEN
      SELECT target.* INTO v_target
      FROM public.adda_vehicle_commission_events AS target
      WHERE target.adda_id=v_event.adda_id AND target.id=v_event.reverses_event_id
      FOR KEY SHARE;
      IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='OWNER_GARI_COMMISSION_REVERSAL_TARGET_MISSING';
      END IF;
      v_expected_type:=CASE
        WHEN v_target.event_type='commission' THEN 'monthly_adda_commission_reversal'
        WHEN v_target.event_type='reissue' THEN 'monthly_adda_commission_correction_reversal_credit'
        WHEN v_target.event_type='adjustment_increase' THEN 'monthly_adda_commission_correction_reversal_credit'
        WHEN v_target.event_type='adjustment_decrease' THEN 'monthly_adda_commission_correction_reversal_debit'
        ELSE NULL END;
      v_expected_amount:=CASE WHEN v_target.event_type='adjustment_decrease'
        THEN -v_event.amount ELSE v_event.amount END;
      v_expected_date:=v_event.reversal_date;
    ELSE
      v_expected_type:=CASE v_event.event_type
        WHEN 'commission' THEN 'monthly_adda_commission'
        WHEN 'reissue' THEN 'monthly_adda_commission_reissue'
        WHEN 'adjustment_increase' THEN 'monthly_adda_commission_adjustment_increase'
        WHEN 'adjustment_decrease' THEN 'monthly_adda_commission_adjustment_decrease'
        ELSE NULL END;
      v_expected_amount:=CASE WHEN v_event.event_type='adjustment_decrease'
        THEN v_event.amount ELSE -v_event.amount END;
      v_expected_date:=v_event.accounting_month;
    END IF;
    IF v_expected_type IS NULL OR NEW.transaction_type IS DISTINCT FROM v_expected_type
       OR NEW.amount IS DISTINCT FROM v_expected_amount
       OR NEW.transaction_date IS DISTINCT FROM v_expected_date THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='OWNER_GARI_COMMISSION_SOURCE_PROJECTION_MISMATCH';
    END IF;
    RETURN NEW;
  END IF;
  IF TG_OP='DELETE' AND OLD.transaction_type IN(
    'monthly_adda_commission','monthly_adda_commission_reversal',
    'monthly_adda_commission_reissue','monthly_adda_commission_adjustment_increase',
    'monthly_adda_commission_adjustment_decrease',
    'monthly_adda_commission_correction_reversal_credit',
    'monthly_adda_commission_correction_reversal_debit'
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='OWNER_GARI_COMMISSION_PROJECTION_APPEND_ONLY';
  END IF;
  IF TG_OP='UPDATE' AND (
    OLD.transaction_type IN(
      'monthly_adda_commission','monthly_adda_commission_reversal',
      'monthly_adda_commission_reissue','monthly_adda_commission_adjustment_increase',
      'monthly_adda_commission_adjustment_decrease',
      'monthly_adda_commission_correction_reversal_credit',
      'monthly_adda_commission_correction_reversal_debit'
    ) OR NEW.transaction_type IN(
      'monthly_adda_commission','monthly_adda_commission_reversal',
      'monthly_adda_commission_reissue','monthly_adda_commission_adjustment_increase',
      'monthly_adda_commission_adjustment_decrease',
      'monthly_adda_commission_correction_reversal_credit',
      'monthly_adda_commission_correction_reversal_debit'
    )
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='OWNER_GARI_COMMISSION_PROJECTION_APPEND_ONLY';
  END IF;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END;
$function$;

CREATE OR REPLACE FUNCTION public.guard_adda_vehicle_commission_events_append_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_target public.adda_vehicle_commission_events%ROWTYPE;
  v_root_id uuid;
  v_effective numeric;
BEGIN
  IF TG_OP='TRUNCATE' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_VEHICLE_COMMISSION_EVENTS_APPEND_ONLY';
  END IF;
  IF TG_OP<>'INSERT' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_VEHICLE_COMMISSION_EVENTS_APPEND_ONLY';
  END IF;
  IF coalesce(pg_catalog.current_setting('ut.adda_finance_rpc',true),'')<>'on' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_VEHICLE_COMMISSION_EVENT_REQUIRES_PROTECTED_RPC';
  END IF;
  IF NEW.event_type='commission' THEN
    IF NEW.reverses_event_id IS NOT NULL OR NEW.reversal_date IS NOT NULL
       OR NEW.reversal_reason IS NOT NULL OR NEW.parent_event_id IS NOT NULL
       OR NEW.root_event_id IS NOT NULL OR NEW.correction_reason IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='INVALID_ADDA_VEHICLE_COMMISSION_ORIGINAL';
    END IF;
  ELSIF NEW.event_type='reversal' THEN
    SELECT target.* INTO v_target
    FROM public.adda_vehicle_commission_events AS target
    WHERE target.adda_id=NEW.adda_id AND target.id=NEW.reverses_event_id
    FOR KEY SHARE;
    IF NOT FOUND OR v_target.event_type NOT IN(
      'commission','reissue','adjustment_increase','adjustment_decrease'
    ) OR NEW.vehicle_id IS DISTINCT FROM v_target.vehicle_id
       OR NEW.accounting_month IS DISTINCT FROM v_target.accounting_month
       OR NEW.amount IS DISTINCT FROM v_target.amount
       OR NEW.reversal_date IS NULL OR NEW.reversal_date<NEW.accounting_month
       OR NULLIF(pg_catalog.btrim(NEW.reversal_reason),'') IS NULL
       OR (NEW.parent_event_id IS NOT NULL AND NEW.parent_event_id IS DISTINCT FROM v_target.id)
       OR (NEW.root_event_id IS NOT NULL
         AND NEW.root_event_id IS DISTINCT FROM coalesce(v_target.root_event_id,v_target.id))
       OR (NEW.root_event_id IS NOT NULL AND NOT EXISTS(
         SELECT 1 FROM public.adda_vehicle_commission_events AS root
         WHERE root.id=NEW.root_event_id AND root.adda_id=NEW.adda_id
           AND root.vehicle_id=NEW.vehicle_id AND root.accounting_month=NEW.accounting_month
           AND root.event_type='commission'
       )) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='INVALID_ADDA_VEHICLE_COMMISSION_REVERSAL';
    END IF;
    IF v_target.event_type IN('commission','reissue') AND EXISTS(
      SELECT 1 FROM public.adda_vehicle_commission_events AS adjustment
      WHERE adjustment.adda_id=v_target.adda_id AND adjustment.parent_event_id=v_target.id
        AND adjustment.event_type IN('adjustment_increase','adjustment_decrease')
        AND NOT EXISTS(
          SELECT 1 FROM public.adda_vehicle_commission_events AS adjustment_reversal
          WHERE adjustment_reversal.adda_id=adjustment.adda_id
            AND adjustment_reversal.reverses_event_id=adjustment.id
        )
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='VEHICLE_COMMISSION_ACTIVE_ADJUSTMENT_REMAINS';
    END IF;
    IF v_target.event_type IN('reissue','adjustment_increase','adjustment_decrease')
       AND EXISTS(
         SELECT 1 FROM public.adda_vehicle_commission_events AS existing_reversal
         WHERE existing_reversal.adda_id=v_target.adda_id
           AND existing_reversal.reverses_event_id=v_target.id
       ) THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='ADDA_VEHICLE_COMMISSION_EVENT_ALREADY_REVERSED';
    END IF;
  ELSIF NEW.event_type='reissue' THEN
    SELECT reversal.* INTO v_target
    FROM public.adda_vehicle_commission_events AS reversal
    WHERE reversal.adda_id=NEW.adda_id AND reversal.id=NEW.parent_event_id
    FOR KEY SHARE;
    IF NOT FOUND OR v_target.event_type<>'reversal'
       OR v_target.vehicle_id IS DISTINCT FROM NEW.vehicle_id
       OR v_target.accounting_month IS DISTINCT FROM NEW.accounting_month
       OR v_target.reverses_event_id IS NULL
       OR NEW.root_event_id IS DISTINCT FROM public.ut_adda_vehicle_commission_root_id(v_target.id) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='INVALID_ADDA_VEHICLE_COMMISSION_REISSUE_LINEAGE';
    END IF;
    SELECT target.* INTO v_target
    FROM public.adda_vehicle_commission_events AS target
    WHERE target.adda_id=NEW.adda_id AND target.id=(
      SELECT reversal.reverses_event_id FROM public.adda_vehicle_commission_events AS reversal
      WHERE reversal.id=NEW.parent_event_id AND reversal.adda_id=NEW.adda_id
    ) FOR KEY SHARE;
    IF NOT FOUND OR v_target.event_type NOT IN('commission','reissue')
       OR v_target.amount IS DISTINCT FROM NEW.amount
       OR v_target.vehicle_id IS DISTINCT FROM NEW.vehicle_id
       OR v_target.accounting_month IS DISTINCT FROM NEW.accounting_month
       OR EXISTS(
         SELECT 1 FROM public.adda_vehicle_commission_events AS adjustment
         WHERE adjustment.adda_id=v_target.adda_id AND adjustment.parent_event_id=v_target.id
           AND adjustment.event_type IN('adjustment_increase','adjustment_decrease')
           AND NOT EXISTS(
             SELECT 1 FROM public.adda_vehicle_commission_events AS reversal
             WHERE reversal.adda_id=adjustment.adda_id AND reversal.reverses_event_id=adjustment.id
           )
       ) OR NOT EXISTS(
         SELECT 1 FROM public.adda_vehicle_commission_events AS root
         WHERE root.id=NEW.root_event_id AND root.adda_id=NEW.adda_id
           AND root.vehicle_id=NEW.vehicle_id AND root.accounting_month=NEW.accounting_month
           AND root.event_type='commission'
       ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='INVALID_ADDA_VEHICLE_COMMISSION_REISSUE_TARGET';
    END IF;
  ELSIF NEW.event_type IN('adjustment_increase','adjustment_decrease') THEN
    SELECT target.* INTO v_target
    FROM public.adda_vehicle_commission_events AS target
    WHERE target.adda_id=NEW.adda_id AND target.id=NEW.parent_event_id
    FOR KEY SHARE;
    IF NOT FOUND OR v_target.event_type NOT IN('commission','reissue')
       OR v_target.vehicle_id IS DISTINCT FROM NEW.vehicle_id
       OR v_target.accounting_month IS DISTINCT FROM NEW.accounting_month
       OR EXISTS(
         SELECT 1 FROM public.adda_vehicle_commission_events AS reversal
         WHERE reversal.adda_id=v_target.adda_id AND reversal.reverses_event_id=v_target.id
       ) OR NEW.root_event_id IS DISTINCT FROM public.ut_adda_vehicle_commission_root_id(v_target.id)
       OR NOT EXISTS(
         SELECT 1 FROM public.adda_vehicle_commission_events AS root
         WHERE root.id=NEW.root_event_id AND root.adda_id=NEW.adda_id
           AND root.vehicle_id=NEW.vehicle_id AND root.accounting_month=NEW.accounting_month
           AND root.event_type='commission'
       ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='INVALID_ADDA_VEHICLE_COMMISSION_ADJUSTMENT_LINEAGE';
    END IF;
    IF NEW.event_type='adjustment_decrease' THEN
      v_root_id:=NEW.root_event_id;
      v_effective:=public.ut_adda_vehicle_commission_effective_root(
        NEW.adda_id,NEW.vehicle_id,v_root_id
      );
      IF NEW.amount>v_effective THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ADDA_VEHICLE_COMMISSION_DECREASE_EXCEEDS_EFFECTIVE_AMOUNT';
      END IF;
    END IF;
  ELSE
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='INVALID_ADDA_VEHICLE_COMMISSION_EVENT_TYPE';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE FUNCTION public.ut_adda_vehicle_commission_root_id(p_event_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $function$
  SELECT coalesce(event.root_event_id,
    CASE WHEN event.event_type='commission' THEN event.id ELSE target.root_event_id END,
    CASE WHEN event.event_type='commission' THEN event.id ELSE target.id END)
  FROM public.adda_vehicle_commission_events AS event
  LEFT JOIN public.adda_vehicle_commission_events AS target
    ON target.adda_id=event.adda_id AND target.id=event.reverses_event_id
  WHERE event.id=p_event_id
$function$;

CREATE FUNCTION public.ut_adda_vehicle_commission_event_effect(p_event_id uuid)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $function$
  SELECT CASE
    WHEN event.event_type IN('commission','reissue','adjustment_increase') THEN event.amount
    WHEN event.event_type='adjustment_decrease' THEN -event.amount
    WHEN event.event_type='reversal' AND target.event_type='adjustment_decrease' THEN event.amount
    WHEN event.event_type='reversal' THEN -event.amount
    ELSE 0::numeric END
  FROM public.adda_vehicle_commission_events AS event
  LEFT JOIN public.adda_vehicle_commission_events AS target
    ON target.adda_id=event.adda_id AND target.id=event.reverses_event_id
  WHERE event.id=p_event_id
$function$;

CREATE FUNCTION public.ut_adda_vehicle_commission_effective_root(
  p_adda_id uuid,p_vehicle_id uuid,p_root_event_id uuid
)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $function$
  SELECT coalesce(sum(public.ut_adda_vehicle_commission_event_effect(event.id)),0)
  FROM public.adda_vehicle_commission_events AS event
  WHERE event.adda_id=p_adda_id AND event.vehicle_id=p_vehicle_id
    AND public.ut_adda_vehicle_commission_root_id(event.id)=p_root_event_id
$function$;

CREATE FUNCTION public.ut_project_adda_vehicle_commission_event(p_event_id uuid,p_actor_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_event public.adda_vehicle_commission_events%ROWTYPE;
  v_target public.adda_vehicle_commission_events%ROWTYPE;
  v_entry public.adda_account_entries%ROWTYPE;
  v_category_id uuid;
  v_category_code text;
  v_entry_kind text;
  v_owner_type text;
  v_owner_amount numeric;
  v_journal_count integer;
  v_owner_count integer;
  v_owner_account_id uuid;
  v_reference_no text;
  v_description text;
BEGIN
  SELECT event.* INTO v_event
  FROM public.adda_vehicle_commission_events AS event
  WHERE event.id=p_event_id FOR UPDATE;
  IF NOT FOUND OR p_actor_id IS NULL OR v_event.amount>999999999999.99 THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='VEHICLE_COMMISSION_PROJECTION_SOURCE_INVALID';
  END IF;
  PERFORM pg_catalog.set_config('ut.adda_finance_rpc','on',true);
  PERFORM pg_catalog.set_config('ut.owner_gari_foundation_sync','on',true);
  PERFORM public.ensure_adda_finance_categories(v_event.adda_id);

  IF v_event.event_type='reversal' THEN
    SELECT target.* INTO v_target
    FROM public.adda_vehicle_commission_events AS target
    WHERE target.adda_id=v_event.adda_id AND target.id=v_event.reverses_event_id;
    SELECT entry.* INTO v_entry
    FROM public.adda_account_entries AS entry
    WHERE entry.adda_id=v_event.adda_id
      AND entry.source_type='vehicle_monthly_commission'
      AND entry.source_id=v_target.id::text AND entry.reverses_entry_id IS NULL
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='VEHICLE_COMMISSION_TARGET_JOURNAL_MISSING';
    END IF;
    v_category_id:=v_entry.category_id;
    v_category_code:=CASE WHEN v_target.event_type='adjustment_decrease'
      THEN 'vehicle_monthly_commission_adjustment' ELSE 'vehicle_monthly_commission' END;
    v_entry_kind:=CASE WHEN v_entry.entry_kind='income' THEN 'expense' ELSE 'income' END;
    v_owner_type:=CASE
      WHEN v_target.event_type='commission' THEN 'monthly_adda_commission_reversal'
      WHEN v_target.event_type IN('reissue','adjustment_increase') THEN 'monthly_adda_commission_correction_reversal_credit'
      WHEN v_target.event_type='adjustment_decrease' THEN 'monthly_adda_commission_correction_reversal_debit'
      ELSE NULL END;
    v_owner_amount:=CASE WHEN v_target.event_type='adjustment_decrease'
      THEN -v_event.amount ELSE v_event.amount END;
    v_reference_no:='Commission correction reversal '||pg_catalog.to_char(v_event.accounting_month,'YYYY-MM');
    v_description:='Monthly vehicle commission correction reversal: '||v_event.reversal_reason;
  ELSE
    v_category_code:=CASE WHEN v_event.event_type='adjustment_decrease'
      THEN 'vehicle_monthly_commission_adjustment' ELSE 'vehicle_monthly_commission' END;
    v_entry_kind:=CASE WHEN v_event.event_type='adjustment_decrease' THEN 'expense' ELSE 'income' END;
    v_owner_type:=CASE v_event.event_type
      WHEN 'commission' THEN 'monthly_adda_commission'
      WHEN 'reissue' THEN 'monthly_adda_commission_reissue'
      WHEN 'adjustment_increase' THEN 'monthly_adda_commission_adjustment_increase'
      WHEN 'adjustment_decrease' THEN 'monthly_adda_commission_adjustment_decrease'
      ELSE NULL END;
    v_owner_amount:=CASE WHEN v_event.event_type='adjustment_decrease'
      THEN v_event.amount ELSE -v_event.amount END;
    v_reference_no:='Vehicle commission '||pg_catalog.to_char(v_event.accounting_month,'YYYY-MM');
    v_description:=CASE v_event.event_type
      WHEN 'reissue' THEN 'Monthly vehicle commission re-issued: '||v_event.correction_reason
      WHEN 'adjustment_increase' THEN 'Monthly vehicle commission increase: '||v_event.correction_reason
      WHEN 'adjustment_decrease' THEN 'Monthly vehicle commission decrease: '||v_event.correction_reason
      ELSE 'Monthly vehicle commission' END;
  END IF;
  IF v_owner_type IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='VEHICLE_COMMISSION_OWNER_TYPE_UNSUPPORTED';
  END IF;

  IF v_category_code='vehicle_monthly_commission_adjustment' THEN
    INSERT INTO public.adda_expense_categories(adda_id,category_code,name,source_policy,is_active,created_by)
    VALUES(v_event.adda_id,v_category_code,'Vehicle Commission Adjustment','system',true,p_actor_id)
    ON CONFLICT(adda_id,category_code) DO NOTHING;
  END IF;
  SELECT category.id INTO v_category_id
  FROM public.adda_expense_categories AS category
  WHERE category.adda_id=v_event.adda_id AND category.category_code=v_category_code
    AND category.source_policy='system'
    AND (category.is_active OR v_event.event_type='reversal')
  FOR SHARE;
  IF v_category_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='VEHICLE_COMMISSION_SYSTEM_CATEGORY_UNAVAILABLE';
  END IF;

  IF v_event.event_type='reversal' THEN
    SELECT count(*)::integer INTO v_journal_count
    FROM public.adda_account_entries AS entry
    WHERE entry.adda_id=v_event.adda_id AND entry.request_id=v_event.request_id
      AND entry.reverses_entry_id=v_entry.id;
  ELSE
    SELECT count(*)::integer INTO v_journal_count
    FROM public.adda_account_entries AS entry
    WHERE entry.adda_id=v_event.adda_id AND entry.source_type='vehicle_monthly_commission'
      AND entry.source_id=v_event.id::text AND entry.reverses_entry_id IS NULL;
  END IF;
  SELECT count(*)::integer INTO v_owner_count
  FROM public.owner_gari_account_transactions AS transaction_row
  WHERE transaction_row.source_commission_event_id=v_event.id
    AND transaction_row.adda_id=v_event.adda_id AND transaction_row.vehicle_id=v_event.vehicle_id;
  IF v_journal_count<>0 OR v_owner_count<>0 THEN
    RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='VEHICLE_COMMISSION_PARTIAL_PROJECTION_CONFLICT';
  END IF;

  INSERT INTO public.adda_account_entries(
    adda_id,entry_date,entry_kind,category_id,amount,source_type,source_id,
    vehicle_id,reference_no,description,reverses_entry_id,request_id,created_by
  ) VALUES(
    v_event.adda_id,
    CASE WHEN v_event.event_type='reversal' THEN v_event.reversal_date ELSE v_event.accounting_month END,
    v_entry_kind,v_category_id,v_event.amount,'vehicle_monthly_commission',
    CASE WHEN v_event.event_type='reversal' THEN v_target.id::text ELSE v_event.id::text END,
    v_event.vehicle_id,v_reference_no,v_description,
    CASE WHEN v_event.event_type='reversal' THEN v_entry.id ELSE NULL END,
    v_event.request_id,p_actor_id
  );

  INSERT INTO public.owner_gari_accounts(adda_id,vehicle_id,created_by)
  VALUES(v_event.adda_id,v_event.vehicle_id,p_actor_id)
  ON CONFLICT(adda_id,vehicle_id) DO NOTHING;
  SELECT account.id INTO v_owner_account_id
  FROM public.owner_gari_accounts AS account
  WHERE account.adda_id=v_event.adda_id AND account.vehicle_id=v_event.vehicle_id
  FOR UPDATE;
  IF v_owner_account_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='OWNER_GARI_ACCOUNT_RESOLUTION_FAILED';
  END IF;
  INSERT INTO public.owner_gari_account_transactions(
    account_id,adda_id,vehicle_id,transaction_date,transaction_type,amount,
    source_commission_event_id,reference_no,description,created_by
  ) VALUES(
    v_owner_account_id,v_event.adda_id,v_event.vehicle_id,
    CASE WHEN v_event.event_type='reversal' THEN v_event.reversal_date ELSE v_event.accounting_month END,
    v_owner_type,v_owner_amount,v_event.id,v_reference_no,v_description,p_actor_id
  );
END;
$function$;

CREATE FUNCTION public.reissue_adda_vehicle_commission(
  p_adda_id uuid,p_reversal_event_id uuid,p_reason text,p_request_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  actor_id uuid:=auth.uid();
  v_adda_id uuid;
  v_reason text:=NULLIF(pg_catalog.btrim(p_reason),'');
  v_reversal public.adda_vehicle_commission_events%ROWTYPE;
  v_target public.adda_vehicle_commission_events%ROWTYPE;
  v_event public.adda_vehicle_commission_events%ROWTYPE;
  v_root_id uuid;
BEGIN
  IF actor_id IS NULL OR p_adda_id IS NULL OR p_reversal_event_id IS NULL
     OR v_reason IS NULL OR pg_catalog.length(v_reason)>500 OR p_request_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_VEHICLE_COMMISSION_REISSUE_REQUEST';
  END IF;
  v_adda_id:=public.ut_other_adda_authorize(p_adda_id,true);
  v_root_id:=public.ut_adda_vehicle_commission_root_id(p_reversal_event_id);
  IF v_root_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='VEHICLE_COMMISSION_REVERSAL_NOT_FOUND';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'vehicle-commission-root:'||v_adda_id::text||':'||v_root_id::text,0));
  PERFORM pg_catalog.set_config('ut.adda_finance_rpc','on',true);
  PERFORM pg_catalog.set_config('ut.owner_gari_foundation_sync','on',true);
  SELECT event.* INTO v_event FROM public.adda_vehicle_commission_events AS event
  WHERE event.adda_id=v_adda_id AND event.request_id=p_request_id FOR UPDATE;
  IF FOUND THEN
    IF v_event.event_type<>'reissue' OR v_event.parent_event_id IS DISTINCT FROM p_reversal_event_id
       OR v_event.correction_reason IS DISTINCT FROM v_reason THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='VEHICLE_COMMISSION_REISSUE_IDEMPOTENCY_MISMATCH';
    END IF;
    IF NOT EXISTS(SELECT 1 FROM public.adda_account_entries entry
      JOIN public.adda_expense_categories category
        ON category.adda_id=entry.adda_id AND category.id=entry.category_id
      WHERE entry.adda_id=v_adda_id AND entry.source_type='vehicle_monthly_commission'
        AND entry.source_id=v_event.id::text AND entry.entry_kind='income'
        AND entry.amount=v_event.amount AND entry.vehicle_id=v_event.vehicle_id
        AND entry.entry_date=v_event.accounting_month AND entry.request_id=v_event.request_id
        AND category.category_code='vehicle_monthly_commission' AND entry.reverses_entry_id IS NULL)
      OR NOT EXISTS(SELECT 1 FROM public.owner_gari_account_transactions transaction_row
      WHERE transaction_row.adda_id=v_adda_id AND transaction_row.source_commission_event_id=v_event.id
        AND transaction_row.transaction_type='monthly_adda_commission_reissue'
        AND transaction_row.vehicle_id=v_event.vehicle_id
        AND transaction_row.transaction_date=v_event.accounting_month
        AND transaction_row.amount=-v_event.amount) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='VEHICLE_COMMISSION_PARTIAL_PROJECTION_CONFLICT';
    END IF;
    RETURN v_event.id;
  END IF;
  SELECT reversal.* INTO v_reversal FROM public.adda_vehicle_commission_events AS reversal
  WHERE reversal.adda_id=v_adda_id AND reversal.id=p_reversal_event_id FOR UPDATE;
  IF NOT FOUND OR v_reversal.event_type<>'reversal' THEN
    RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='VEHICLE_COMMISSION_REVERSAL_NOT_FOUND';
  END IF;
  SELECT target.* INTO v_target FROM public.adda_vehicle_commission_events AS target
  WHERE target.adda_id=v_adda_id AND target.id=v_reversal.reverses_event_id FOR UPDATE;
  IF NOT FOUND OR v_target.event_type NOT IN('commission','reissue') THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='VEHICLE_COMMISSION_REISSUE_TARGET_INVALID';
  END IF;
  IF EXISTS(SELECT 1 FROM public.adda_vehicle_commission_events child
    WHERE child.adda_id=v_adda_id AND child.parent_event_id=v_reversal.id AND child.event_type='reissue') THEN
    RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='VEHICLE_COMMISSION_ALREADY_REISSUED';
  END IF;
  IF EXISTS(SELECT 1 FROM public.adda_vehicle_commission_events adjustment
    WHERE adjustment.adda_id=v_adda_id AND adjustment.parent_event_id=v_target.id
      AND adjustment.event_type IN('adjustment_increase','adjustment_decrease')
      AND NOT EXISTS(SELECT 1 FROM public.adda_vehicle_commission_events reversal
        WHERE reversal.adda_id=adjustment.adda_id AND reversal.reverses_event_id=adjustment.id)) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='VEHICLE_COMMISSION_ACTIVE_ADJUSTMENT_REMAINS';
  END IF;
  v_root_id:=public.ut_adda_vehicle_commission_root_id(v_target.id);
  IF v_root_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='VEHICLE_COMMISSION_ROOT_NOT_FOUND';
  END IF;
  INSERT INTO public.adda_vehicle_commission_events(
    adda_id,vehicle_id,accounting_month,amount,event_type,request_id,
    parent_event_id,root_event_id,correction_reason,created_by
  ) VALUES(
    v_adda_id,v_target.vehicle_id,v_target.accounting_month,v_target.amount,'reissue',p_request_id,
    v_reversal.id,v_root_id,v_reason,actor_id
  ) RETURNING * INTO v_event;
  PERFORM public.ut_project_adda_vehicle_commission_event(v_event.id,actor_id);
  RETURN v_event.id;
END;
$function$;

CREATE FUNCTION public.adjust_adda_vehicle_commission(
  p_adda_id uuid,p_target_event_id uuid,p_direction text,p_amount numeric,p_reason text,p_request_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  actor_id uuid:=auth.uid();
  v_adda_id uuid;
  v_reason text:=NULLIF(pg_catalog.btrim(p_reason),'');
  v_target public.adda_vehicle_commission_events%ROWTYPE;
  v_event public.adda_vehicle_commission_events%ROWTYPE;
  v_root_id uuid;
  v_effective numeric;
  v_event_type text;
BEGIN
  IF actor_id IS NULL OR p_adda_id IS NULL OR p_target_event_id IS NULL
     OR p_direction IS NULL OR p_direction NOT IN('increase','decrease')
     OR p_amount IS NULL OR p_amount<=0 OR p_amount<>pg_catalog.round(p_amount,2)
     OR p_amount::text IN('NaN','Infinity','-Infinity') OR v_reason IS NULL
     OR pg_catalog.length(v_reason)>500 OR p_request_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_VEHICLE_COMMISSION_ADJUSTMENT_REQUEST';
  END IF;
  v_adda_id:=public.ut_other_adda_authorize(p_adda_id,true);
  v_root_id:=public.ut_adda_vehicle_commission_root_id(p_target_event_id);
  IF v_root_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='VEHICLE_COMMISSION_ADJUSTMENT_TARGET_NOT_FOUND';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'vehicle-commission-root:'||v_adda_id::text||':'||v_root_id::text,0));
  PERFORM pg_catalog.set_config('ut.adda_finance_rpc','on',true);
  PERFORM pg_catalog.set_config('ut.owner_gari_foundation_sync','on',true);
  SELECT event.* INTO v_event FROM public.adda_vehicle_commission_events AS event
  WHERE event.adda_id=v_adda_id AND event.request_id=p_request_id FOR UPDATE;
  IF FOUND THEN
    v_event_type:=CASE WHEN p_direction='increase'
      THEN 'adjustment_increase' ELSE 'adjustment_decrease' END;
    IF v_event.event_type IS DISTINCT FROM v_event_type
      OR v_event.parent_event_id IS DISTINCT FROM p_target_event_id
      OR v_event.amount IS DISTINCT FROM p_amount OR v_event.correction_reason IS DISTINCT FROM v_reason THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='VEHICLE_COMMISSION_ADJUSTMENT_IDEMPOTENCY_MISMATCH';
    END IF;
    IF NOT EXISTS(SELECT 1 FROM public.adda_account_entries entry
      JOIN public.adda_expense_categories category
        ON category.adda_id=entry.adda_id AND category.id=entry.category_id
      WHERE entry.adda_id=v_adda_id AND entry.source_type='vehicle_monthly_commission'
        AND entry.source_id=v_event.id::text AND entry.amount=v_event.amount
        AND entry.vehicle_id=v_event.vehicle_id AND entry.entry_date=v_event.accounting_month
        AND entry.request_id=v_event.request_id
        AND entry.entry_kind=CASE WHEN v_event.event_type='adjustment_decrease' THEN 'expense' ELSE 'income' END
        AND category.category_code=CASE WHEN v_event.event_type='adjustment_decrease'
          THEN 'vehicle_monthly_commission_adjustment' ELSE 'vehicle_monthly_commission' END
        AND entry.reverses_entry_id IS NULL)
      OR NOT EXISTS(SELECT 1 FROM public.owner_gari_account_transactions transaction_row
      WHERE transaction_row.adda_id=v_adda_id AND transaction_row.source_commission_event_id=v_event.id
        AND transaction_row.vehicle_id=v_event.vehicle_id
        AND transaction_row.transaction_date=v_event.accounting_month
        AND transaction_row.transaction_type=CASE WHEN v_event.event_type='adjustment_decrease'
          THEN 'monthly_adda_commission_adjustment_decrease' ELSE 'monthly_adda_commission_adjustment_increase' END
        AND transaction_row.amount=CASE WHEN v_event.event_type='adjustment_decrease'
          THEN v_event.amount ELSE -v_event.amount END) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='VEHICLE_COMMISSION_PARTIAL_PROJECTION_CONFLICT';
    END IF;
    RETURN v_event.id;
  END IF;
  SELECT target.* INTO v_target FROM public.adda_vehicle_commission_events AS target
  WHERE target.adda_id=v_adda_id AND target.id=p_target_event_id FOR UPDATE;
  IF NOT FOUND OR v_target.event_type NOT IN('commission','reissue')
     OR EXISTS(SELECT 1 FROM public.adda_vehicle_commission_events reversal
       WHERE reversal.adda_id=v_adda_id AND reversal.reverses_event_id=v_target.id) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='VEHICLE_COMMISSION_ADJUSTMENT_TARGET_NOT_ACTIVE';
  END IF;
  v_root_id:=public.ut_adda_vehicle_commission_root_id(v_target.id);
  v_effective:=public.ut_adda_vehicle_commission_effective_root(v_adda_id,v_target.vehicle_id,v_root_id);
  IF p_direction='decrease' AND p_amount>v_effective THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='VEHICLE_COMMISSION_DECREASE_EXCEEDS_EFFECTIVE_AMOUNT';
  END IF;
  IF p_amount>999999999999.99 THEN
    RAISE EXCEPTION USING ERRCODE='22003',MESSAGE='VEHICLE_COMMISSION_EXCEEDS_OWNER_ACCOUNT_AMOUNT_RANGE';
  END IF;
  v_event_type:=CASE WHEN p_direction='increase' THEN 'adjustment_increase' ELSE 'adjustment_decrease' END;
  INSERT INTO public.adda_vehicle_commission_events(
    adda_id,vehicle_id,accounting_month,amount,event_type,request_id,
    parent_event_id,root_event_id,correction_reason,created_by
  ) VALUES(
    v_adda_id,v_target.vehicle_id,v_target.accounting_month,p_amount,v_event_type,p_request_id,
    v_target.id,v_root_id,v_reason,actor_id
  ) RETURNING * INTO v_event;
  PERFORM public.ut_project_adda_vehicle_commission_event(v_event.id,actor_id);
  RETURN v_event.id;
END;
$function$;

CREATE FUNCTION public.reverse_adda_vehicle_commission_correction(
  p_adda_id uuid,p_target_event_id uuid,p_reversal_date date,p_reason text,p_request_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  actor_id uuid:=auth.uid();
  v_adda_id uuid;
  v_reason text:=NULLIF(pg_catalog.btrim(p_reason),'');
  v_target public.adda_vehicle_commission_events%ROWTYPE;
  v_event public.adda_vehicle_commission_events%ROWTYPE;
  v_root_id uuid;
BEGIN
  IF actor_id IS NULL OR p_adda_id IS NULL OR p_target_event_id IS NULL
     OR p_reversal_date IS NULL OR v_reason IS NULL OR pg_catalog.length(v_reason)>500
     OR p_request_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_VEHICLE_COMMISSION_CORRECTION_REVERSAL_REQUEST';
  END IF;
  v_adda_id:=public.ut_other_adda_authorize(p_adda_id,true);
  v_root_id:=public.ut_adda_vehicle_commission_root_id(p_target_event_id);
  IF v_root_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='VEHICLE_COMMISSION_CORRECTION_TARGET_NOT_FOUND';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'vehicle-commission-root:'||v_adda_id::text||':'||v_root_id::text,0));
  PERFORM pg_catalog.set_config('ut.adda_finance_rpc','on',true);
  PERFORM pg_catalog.set_config('ut.owner_gari_foundation_sync','on',true);
  SELECT event.* INTO v_event FROM public.adda_vehicle_commission_events AS event
  WHERE event.adda_id=v_adda_id AND event.request_id=p_request_id FOR UPDATE;
  IF FOUND THEN
    IF v_event.event_type<>'reversal' OR v_event.reverses_event_id IS DISTINCT FROM p_target_event_id
       OR v_event.reversal_date IS DISTINCT FROM p_reversal_date
       OR v_event.reversal_reason IS DISTINCT FROM v_reason THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='VEHICLE_COMMISSION_CORRECTION_REVERSAL_IDEMPOTENCY_MISMATCH';
    END IF;
    SELECT target.* INTO v_target FROM public.adda_vehicle_commission_events AS target
    WHERE target.adda_id=v_adda_id AND target.id=p_target_event_id;
    IF NOT FOUND OR v_event.vehicle_id IS DISTINCT FROM v_target.vehicle_id
       OR v_event.accounting_month IS DISTINCT FROM v_target.accounting_month
       OR v_event.amount IS DISTINCT FROM v_target.amount
       OR NOT EXISTS(SELECT 1 FROM public.adda_account_entries reversal_entry
      JOIN public.adda_account_entries original_entry
        ON original_entry.id=reversal_entry.reverses_entry_id
       AND original_entry.adda_id=reversal_entry.adda_id
      WHERE reversal_entry.adda_id=v_adda_id AND reversal_entry.request_id=p_request_id
        AND reversal_entry.entry_kind=CASE WHEN original_entry.entry_kind='income' THEN 'expense' ELSE 'income' END
        AND reversal_entry.amount=v_target.amount AND reversal_entry.vehicle_id=v_target.vehicle_id
        AND reversal_entry.entry_date=p_reversal_date
        AND reversal_entry.source_type='vehicle_monthly_commission'
        AND reversal_entry.source_id=v_target.id::text
        AND original_entry.source_type='vehicle_monthly_commission'
        AND original_entry.source_id=v_target.id::text
        AND original_entry.reverses_entry_id IS NULL)
      OR NOT EXISTS(SELECT 1 FROM public.owner_gari_account_transactions transaction_row
      WHERE transaction_row.adda_id=v_adda_id AND transaction_row.vehicle_id=v_target.vehicle_id
        AND transaction_row.source_commission_event_id=v_event.id
        AND transaction_row.transaction_date=p_reversal_date
        AND transaction_row.transaction_type=CASE WHEN v_target.event_type='adjustment_decrease'
          THEN 'monthly_adda_commission_correction_reversal_debit'
          ELSE 'monthly_adda_commission_correction_reversal_credit' END
        AND transaction_row.amount=CASE WHEN v_target.event_type='adjustment_decrease'
          THEN -v_event.amount ELSE v_event.amount END) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='VEHICLE_COMMISSION_PARTIAL_PROJECTION_CONFLICT';
    END IF;
    RETURN v_event.id;
  END IF;
  SELECT target.* INTO v_target FROM public.adda_vehicle_commission_events AS target
  WHERE target.adda_id=v_adda_id AND target.id=p_target_event_id FOR UPDATE;
  IF NOT FOUND OR v_target.event_type NOT IN('reissue','adjustment_increase','adjustment_decrease')
     OR p_reversal_date<v_target.accounting_month
     OR EXISTS(SELECT 1 FROM public.adda_vehicle_commission_events reversal
       WHERE reversal.adda_id=v_adda_id AND reversal.reverses_event_id=v_target.id) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='VEHICLE_COMMISSION_CORRECTION_TARGET_NOT_REVERSIBLE';
  END IF;
  IF v_target.event_type='reissue' AND EXISTS(
    SELECT 1 FROM public.adda_vehicle_commission_events adjustment
    WHERE adjustment.adda_id=v_adda_id AND adjustment.parent_event_id=v_target.id
      AND adjustment.event_type IN('adjustment_increase','adjustment_decrease')
      AND NOT EXISTS(SELECT 1 FROM public.adda_vehicle_commission_events reversal
        WHERE reversal.adda_id=adjustment.adda_id AND reversal.reverses_event_id=adjustment.id)
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='VEHICLE_COMMISSION_ACTIVE_ADJUSTMENT_REMAINS';
  END IF;
  v_root_id:=public.ut_adda_vehicle_commission_root_id(v_target.id);
  INSERT INTO public.adda_vehicle_commission_events(
    adda_id,vehicle_id,accounting_month,amount,event_type,request_id,
    reverses_event_id,reversal_date,reversal_reason,parent_event_id,root_event_id,created_by
  ) VALUES(
    v_adda_id,v_target.vehicle_id,v_target.accounting_month,v_target.amount,'reversal',p_request_id,
    v_target.id,p_reversal_date,v_reason,v_target.id,v_root_id,actor_id
  ) RETURNING * INTO v_event;
  PERFORM public.ut_project_adda_vehicle_commission_event(v_event.id,actor_id);
  RETURN v_event.id;
END;
$function$;

CREATE FUNCTION public.get_adda_vehicle_commission_history_v2(p_adda_id uuid,p_limit integer DEFAULT 200)
RETURNS TABLE(
  event_id uuid,event_type text,adda_id uuid,vehicle_id uuid,vehicle_no text,owner_name text,
  accounting_month date,amount numeric,signed_effect numeric,parent_event_id uuid,root_event_id uuid,
  reverses_event_id uuid,correction_reason text,created_at timestamptz,reversal_event_id uuid,
  reversal_date date,reversal_reason text,reversal_status text,root_original_amount numeric,
  total_reversals numeric,total_reissues numeric,total_adjustment_increases numeric,
  total_adjustment_decreases numeric,effective_root_amount numeric,effective_root_status text,
  active_charge_event_id uuid,can_reverse boolean,can_reissue boolean,can_adjust boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE v_adda_id uuid;
BEGIN
  IF p_adda_id IS NULL OR p_limit IS NULL OR p_limit<1 OR p_limit>500 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_VEHICLE_COMMISSION_HISTORY_REQUEST';
  END IF;
  v_adda_id:=public.ut_resolve_adda_accounting_tenant(p_adda_id);
  RETURN QUERY
  WITH event_rows AS (
    SELECT event.*,public.ut_adda_vehicle_commission_root_id(event.id) AS resolved_root_id,
      reversal.id AS reversal_id,reversal.reversal_date AS linked_reversal_date,
      reversal.reversal_reason AS linked_reversal_reason
    FROM public.adda_vehicle_commission_events AS event
    LEFT JOIN public.adda_vehicle_commission_events AS reversal
      ON reversal.adda_id=event.adda_id AND reversal.reverses_event_id=event.id
     AND reversal.event_type='reversal'
    WHERE event.adda_id=v_adda_id
  ), root_totals AS (
    SELECT event_row.resolved_root_id AS root_id,
      max(root.amount) FILTER(WHERE root.event_type='commission') AS original_amount,
      coalesce(sum(event_row.amount) FILTER(WHERE event_row.event_type='reversal'),0) AS total_reversals,
      coalesce(sum(event_row.amount) FILTER(WHERE event_row.event_type='reissue'),0) AS total_reissues,
      coalesce(sum(event_row.amount) FILTER(WHERE event_row.event_type='adjustment_increase'),0) AS total_increases,
      coalesce(sum(event_row.amount) FILTER(WHERE event_row.event_type='adjustment_decrease'),0) AS total_decreases,
      public.ut_adda_vehicle_commission_effective_root(v_adda_id,root.vehicle_id,event_row.resolved_root_id) AS effective_amount
    FROM event_rows AS event_row
    JOIN public.adda_vehicle_commission_events AS root
      ON root.adda_id=v_adda_id AND root.id=event_row.resolved_root_id AND root.event_type='commission'
    GROUP BY event_row.resolved_root_id,root.vehicle_id
  ), active_charges AS (
    SELECT DISTINCT ON(event_row.resolved_root_id) event_row.resolved_root_id,event_row.id
    FROM event_rows AS event_row
    WHERE event_row.event_type IN('commission','reissue') AND event_row.reversal_id IS NULL
    ORDER BY event_row.resolved_root_id,event_row.created_at DESC,event_row.id DESC
  )
  SELECT event_row.id,event_row.event_type,event_row.adda_id,event_row.vehicle_id,vehicle.vehicle_no,vehicle.owner_name,
    event_row.accounting_month,event_row.amount,public.ut_adda_vehicle_commission_event_effect(event_row.id),
    event_row.parent_event_id,event_row.resolved_root_id,event_row.reverses_event_id,
    coalesce(event_row.correction_reason,event_row.reversal_reason,event_row.linked_reversal_reason),event_row.created_at,
    event_row.reversal_id,coalesce(event_row.reversal_date,event_row.linked_reversal_date),
    coalesce(event_row.reversal_reason,event_row.linked_reversal_reason),
    CASE WHEN event_row.event_type='reversal' THEN 'Reversal'
      WHEN event_row.reversal_id IS NOT NULL THEN 'Reversed'
      WHEN event_row.event_type='adjustment_decrease' THEN 'Adjustment decrease'
      WHEN event_row.event_type='adjustment_increase' THEN 'Adjustment increase'
      WHEN event_row.event_type='reissue' THEN 'Re-issued'
      ELSE 'Active' END,
    totals.original_amount,totals.total_reversals,totals.total_reissues,
    totals.total_increases,totals.total_decreases,totals.effective_amount,
    CASE WHEN totals.effective_amount<=0 THEN 'Zeroed'
      WHEN active_charge.id IS NULL THEN 'Reversed'
      WHEN totals.total_reissues>0 THEN 'Reissued'
      WHEN totals.total_increases>0 OR totals.total_decreases>0 THEN 'Adjusted'
      ELSE 'Active' END,
    active_charge.id,
    (event_row.event_type IN('commission','reissue','adjustment_increase','adjustment_decrease')
      AND event_row.reversal_id IS NULL
      AND (event_row.event_type IN('adjustment_increase','adjustment_decrease') OR NOT EXISTS(
        SELECT 1 FROM public.adda_vehicle_commission_events AS adjustment
        WHERE adjustment.adda_id=event_row.adda_id AND adjustment.parent_event_id=event_row.id
          AND adjustment.event_type IN('adjustment_increase','adjustment_decrease')
          AND NOT EXISTS(SELECT 1 FROM public.adda_vehicle_commission_events AS adjustment_reversal
            WHERE adjustment_reversal.adda_id=adjustment.adda_id
              AND adjustment_reversal.reverses_event_id=adjustment.id)
      ))),
    (event_row.event_type='reversal'
      AND EXISTS(SELECT 1 FROM public.adda_vehicle_commission_events AS target
        WHERE target.adda_id=event_row.adda_id AND target.id=event_row.reverses_event_id
          AND target.event_type IN('commission','reissue'))
      AND NOT EXISTS(SELECT 1 FROM public.adda_vehicle_commission_events AS replacement
        WHERE replacement.adda_id=event_row.adda_id AND replacement.parent_event_id=event_row.id
          AND replacement.event_type='reissue')
      AND NOT EXISTS(SELECT 1 FROM public.adda_vehicle_commission_events AS adjustment
        WHERE adjustment.adda_id=event_row.adda_id AND adjustment.parent_event_id=event_row.reverses_event_id
          AND adjustment.event_type IN('adjustment_increase','adjustment_decrease')
          AND NOT EXISTS(SELECT 1 FROM public.adda_vehicle_commission_events AS adjustment_reversal
            WHERE adjustment_reversal.adda_id=adjustment.adda_id
              AND adjustment_reversal.reverses_event_id=adjustment.id))),
    (event_row.event_type IN('commission','reissue') AND event_row.reversal_id IS NULL
      AND active_charge.id=event_row.id)
  FROM event_rows AS event_row
  JOIN public.vehicles AS vehicle ON vehicle.id=event_row.vehicle_id AND vehicle.adda_id=event_row.adda_id
  LEFT JOIN root_totals AS totals ON totals.root_id=event_row.resolved_root_id
  LEFT JOIN active_charges AS active_charge ON active_charge.resolved_root_id=event_row.resolved_root_id
  ORDER BY event_row.accounting_month DESC,event_row.created_at DESC,event_row.id DESC
  LIMIT p_limit;
END;
$function$;

CREATE FUNCTION public.get_owner_gari_account_statement_v3(
  p_vehicle_id uuid,p_month date DEFAULT NULL,p_date_from date DEFAULT NULL,
  p_date_to date DEFAULT NULL,p_transaction_type text DEFAULT NULL,
  p_movement_group_id uuid DEFAULT NULL,p_search text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_report jsonb;
  v_adda_id uuid;
  v_total_commission numeric;
  v_transactions jsonb;
  v_allowed_types text[]:=ARRAY[
    'opening_seed','chakkar_net_credit','owner_withdrawal','gari_withdrawal',
    'monthly_adda_commission','monthly_adda_commission_reversal',
    'monthly_adda_commission_reissue','monthly_adda_commission_adjustment_increase',
    'monthly_adda_commission_adjustment_decrease',
    'monthly_adda_commission_correction_reversal_credit',
    'monthly_adda_commission_correction_reversal_debit',
    'adjustment_credit','adjustment_debit','voucher_adjustment_expense'
  ];
BEGIN
  IF p_transaction_type IS NOT NULL AND NOT(p_transaction_type=ANY(v_allowed_types)) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_OWNER_GARI_TRANSACTION_TYPE';
  END IF;
  v_report:=public.get_owner_gari_account_statement_v2(
    p_vehicle_id,p_month,p_date_from,p_date_to,NULL,p_movement_group_id,p_search
  );
  v_adda_id:=(v_report->'account'->>'adda_id')::uuid;
  SELECT coalesce(-sum(transaction_row.amount),0)
  INTO v_total_commission
  FROM public.owner_gari_account_transactions AS transaction_row
  WHERE transaction_row.adda_id=v_adda_id AND transaction_row.vehicle_id=p_vehicle_id
    AND transaction_row.transaction_type=ANY(ARRAY[
      'monthly_adda_commission','monthly_adda_commission_reversal',
      'monthly_adda_commission_reissue','monthly_adda_commission_adjustment_increase',
      'monthly_adda_commission_adjustment_decrease',
      'monthly_adda_commission_correction_reversal_credit',
      'monthly_adda_commission_correction_reversal_debit'
    ])
    AND ((v_report->'period'->>'date_from') IS NULL
      OR transaction_row.transaction_date>=(v_report->'period'->>'date_from')::date)
    AND ((v_report->'period'->>'date_to') IS NULL
      OR transaction_row.transaction_date<=(v_report->'period'->>'date_to')::date);
  SELECT coalesce(pg_catalog.jsonb_agg(
    transaction_row.value || pg_catalog.jsonb_build_object(
      'credit',CASE WHEN commission_event.id IS NOT NULL
        THEN greatest(coalesce((transaction_row.value->>'signed_amount')::numeric,0),0)
        ELSE coalesce((transaction_row.value->>'credit')::numeric,0) END,
      'debit',CASE WHEN commission_event.id IS NOT NULL
        THEN greatest(-coalesce((transaction_row.value->>'signed_amount')::numeric,0),0)
        ELSE coalesce((transaction_row.value->>'debit')::numeric,0) END,
      'source_commission_event_id',commission_event.id,
      'commission_event_type',commission_event.event_type,
      'commission_month',commission_event.accounting_month,
      'commission_parent_event_id',commission_event.parent_event_id,
      'commission_root_event_id',public.ut_adda_vehicle_commission_root_id(commission_event.id),
      'commission_correction_reason',coalesce(commission_event.correction_reason,commission_event.reversal_reason),
      'commission_effective_root_amount',public.ut_adda_vehicle_commission_effective_root(
        commission_event.adda_id,commission_event.vehicle_id,
        public.ut_adda_vehicle_commission_root_id(commission_event.id)),
      'commission_status',CASE WHEN commission_event.event_type='reversal' THEN 'reversal'
        WHEN commission_reversal.id IS NOT NULL THEN 'reversed'
        WHEN commission_event.id IS NOT NULL THEN 'active' ELSE NULL END
    ) ORDER BY transaction_row.ordinality
  ),'[]'::jsonb)
  INTO v_transactions
  FROM pg_catalog.jsonb_array_elements(v_report->'transactions') WITH ORDINALITY
    AS transaction_row(value,ordinality)
  LEFT JOIN public.owner_gari_account_transactions AS owner_transaction
    ON owner_transaction.id=(transaction_row.value->>'transaction_id')::uuid
   AND owner_transaction.adda_id=v_adda_id AND owner_transaction.vehicle_id=p_vehicle_id
  LEFT JOIN public.adda_vehicle_commission_events AS commission_event
    ON commission_event.id=owner_transaction.source_commission_event_id
   AND commission_event.adda_id=v_adda_id AND commission_event.vehicle_id=p_vehicle_id
  LEFT JOIN public.adda_vehicle_commission_events AS commission_reversal
    ON commission_reversal.adda_id=commission_event.adda_id
   AND commission_reversal.reverses_event_id=commission_event.id
   AND commission_reversal.event_type='reversal'
  WHERE p_transaction_type IS NULL OR transaction_row.value->>'transaction_type'=p_transaction_type;
  v_report:=pg_catalog.jsonb_set(v_report,'{transactions}',v_transactions,true);
  v_report:=pg_catalog.jsonb_set(v_report,'{summary}',
    coalesce(v_report->'summary','{}'::jsonb)
      || pg_catalog.jsonb_build_object('total_monthly_commission',v_total_commission),true);
  RETURN v_report;
END;
$function$;

REVOKE ALL ON FUNCTION public.ut_adda_vehicle_commission_root_id(uuid),
  public.ut_adda_vehicle_commission_event_effect(uuid),
  public.ut_adda_vehicle_commission_effective_root(uuid,uuid,uuid),
  public.ut_project_adda_vehicle_commission_event(uuid,uuid)
FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.reissue_adda_vehicle_commission(uuid,uuid,text,uuid),
  public.adjust_adda_vehicle_commission(uuid,uuid,text,numeric,text,uuid),
  public.reverse_adda_vehicle_commission_correction(uuid,uuid,date,text,uuid),
  public.get_adda_vehicle_commission_history_v2(uuid,integer),
  public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)
FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reissue_adda_vehicle_commission(uuid,uuid,text,uuid),
  public.adjust_adda_vehicle_commission(uuid,uuid,text,numeric,text,uuid),
  public.reverse_adda_vehicle_commission_correction(uuid,uuid,date,text,uuid)
TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_adda_vehicle_commission_history_v2(uuid,integer),
  public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)
TO authenticated,service_role;

COMMENT ON COLUMN public.adda_vehicle_commission_events.parent_event_id IS
  'Phase 5B append-only lineage parent; correction events point to the reversal or active charge they correct.';
COMMENT ON COLUMN public.adda_vehicle_commission_events.root_event_id IS
  'Phase 5B original commission root; legacy event roots remain derivable and are not backfilled.';
COMMENT ON COLUMN public.adda_vehicle_commission_events.correction_reason IS
  'Required explanation for reissue and commission adjustment events.';
COMMENT ON FUNCTION public.reissue_adda_vehicle_commission(uuid,uuid,text,uuid) IS
  'Append-only reissue paired atomically to Adda Account and Owner/Gari projections; no Cashbook movement.';
COMMENT ON FUNCTION public.adjust_adda_vehicle_commission(uuid,uuid,text,numeric,text,uuid) IS
  'Append-only difference-only monthly vehicle commission adjustment with a zero-floor decrease guard.';
COMMENT ON FUNCTION public.reverse_adda_vehicle_commission_correction(uuid,uuid,date,text,uuid) IS
  'Append-only compensating event and paired projections for a reissue or adjustment; no Cashbook movement.';

COMMIT;
