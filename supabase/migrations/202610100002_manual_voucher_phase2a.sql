BEGIN;

DO $phase2a_preconditions$
DECLARE
  owner_type_check text;
  owner_source_check text;
BEGIN
  IF pg_catalog.to_regclass('public.expenses') IS NULL
     OR pg_catalog.to_regclass('public.expense_items') IS NULL
     OR pg_catalog.to_regclass('public.manual_voucher_details') IS NULL
     OR pg_catalog.to_regclass('public.manual_voucher_freight_items') IS NULL
     OR pg_catalog.to_regclass('public.owner_gari_accounts') IS NULL
     OR pg_catalog.to_regclass('public.owner_gari_account_transactions') IS NULL
     OR pg_catalog.to_regclass('public.vehicles') IS NULL
     OR pg_catalog.to_regclass('public.drivers') IS NULL
     OR pg_catalog.to_regclass('public.profiles') IS NULL
     OR pg_catalog.to_regclass('public.addas') IS NULL
     OR pg_catalog.to_regclass('public.vehicle_chakkar_settlements') IS NULL
     OR pg_catalog.to_regprocedure('public.save_manual_voucher(bigint,text,date,uuid,uuid,integer,text,jsonb)') IS NULL
     OR pg_catalog.to_regprocedure('public.delete_manual_voucher_draft(bigint)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_sync_voucher_item_cashbook_trigger()') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_guard_owner_gari_commission_append_only()') IS NULL
     OR pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)') IS NULL
     OR pg_catalog.to_regprocedure('public.get_vehicle_monthly_hisab(uuid,date,date,date)') IS NULL
     OR pg_catalog.to_regprocedure('public.current_user_role()') IS NULL
     OR pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NULL
     OR pg_catalog.to_regprocedure('public.is_super_admin()') IS NULL THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_PHASE2A_REQUIRED_FOUNDATION_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc procedure_row
    JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=procedure_row.pronamespace
    WHERE namespace_row.nspname='public'
      AND procedure_row.proname IN(
        'save_manual_voucher_expense_items','save_manual_voucher_phase2','finalize_manual_voucher',
        'get_owner_gari_account_statement_v4','get_vehicle_monthly_hisab_v2',
        'ut_guard_manual_voucher_phase2a','ut_guard_manual_owner_gari_projection'
      )
  ) OR pg_catalog.to_regclass('public.manual_vehicle_chakkar_settlements') IS NOT NULL
    OR pg_catalog.to_regclass('public.manual_vehicle_chakkar_settlements_vehicle_date_idx') IS NOT NULL
    OR pg_catalog.to_regclass('public.owner_gari_transactions_manual_settlement_uidx') IS NOT NULL
    OR EXISTS (
      SELECT 1 FROM information_schema.columns column_row
      WHERE column_row.table_schema='public'
        AND column_row.table_name='owner_gari_account_transactions'
        AND column_row.column_name='source_manual_settlement_id'
    ) OR EXISTS (
      SELECT 1 FROM information_schema.columns column_row
      WHERE column_row.table_schema='public' AND column_row.table_name='manual_voucher_details'
        AND column_row.column_name IN('finalized_at','finalized_by')
    ) OR EXISTS (
      SELECT 1 FROM pg_catalog.pg_trigger trigger_row
      WHERE NOT trigger_row.tgisinternal AND (
        (trigger_row.tgrelid='public.expenses'::pg_catalog.regclass
          AND trigger_row.tgname='expenses_manual_voucher_phase2a_guard')
        OR (trigger_row.tgrelid='public.manual_voucher_details'::pg_catalog.regclass
          AND trigger_row.tgname='manual_voucher_details_phase2a_guard')
        OR (trigger_row.tgrelid='public.manual_voucher_freight_items'::pg_catalog.regclass
          AND trigger_row.tgname='manual_voucher_freight_items_phase2a_guard')
        OR (trigger_row.tgrelid='public.owner_gari_account_transactions'::pg_catalog.regclass
          AND trigger_row.tgname='owner_gari_manual_projection_guard')
        OR (trigger_row.tgrelid=pg_catalog.to_regclass('public.manual_vehicle_chakkar_settlements')
          AND trigger_row.tgname='manual_vehicle_chakkar_settlements_append_only')
      )
    ) THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_PHASE2A_OBJECT_NAME_COLLISION';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint constraint_row
    WHERE constraint_row.conrelid='public.manual_voucher_details'::pg_catalog.regclass
      AND constraint_row.conname='manual_voucher_details_status_check'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger trigger_row
    WHERE trigger_row.tgrelid='public.expense_items'::pg_catalog.regclass
      AND trigger_row.tgname='expense_items_protect_manual_voucher'
      AND NOT trigger_row.tgisinternal
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger trigger_row
    WHERE trigger_row.tgrelid='public.expense_items'::pg_catalog.regclass
      AND trigger_row.tgname='expense_items_sync_voucher_cashbook'
      AND NOT trigger_row.tgisinternal
  ) THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_PHASE2A_PHASE1_GUARDS_MISSING';
  END IF;

  SELECT pg_catalog.pg_get_constraintdef(constraint_row.oid)
  INTO owner_type_check
  FROM pg_catalog.pg_constraint constraint_row
  WHERE constraint_row.conrelid='public.owner_gari_account_transactions'::pg_catalog.regclass
    AND constraint_row.conname='owner_gari_transactions_type_check';
  SELECT pg_catalog.pg_get_constraintdef(constraint_row.oid)
  INTO owner_source_check
  FROM pg_catalog.pg_constraint constraint_row
  WHERE constraint_row.conrelid='public.owner_gari_account_transactions'::pg_catalog.regclass
    AND constraint_row.conname='owner_gari_transactions_commission_source_check';
  IF owner_type_check IS NULL OR owner_source_check IS NULL
     OR owner_type_check NOT LIKE '%voucher_adjustment_expense%'
     OR owner_source_check NOT LIKE '%source_commission_event_id%' THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_PHASE2A_OWNER_GARI_CONTRACT_CHANGED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.expense_items item
    JOIN public.expenses voucher ON voucher.id=item.expense_id
    WHERE voucher.voucher_source='manual'
  ) THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_PHASE2A_UNEXPECTED_MANUAL_EXPENSE_ROWS';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.owner_gari_account_transactions transaction_row
    WHERE transaction_row.transaction_type='manual_chakkar_net'
  ) THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_PHASE2A_UNEXPECTED_OWNER_GARI_ROWS';
  END IF;
END
$phase2a_preconditions$;

ALTER TABLE public.manual_voucher_details
  ADD COLUMN finalized_at timestamptz,
  ADD COLUMN finalized_by uuid,
  DROP CONSTRAINT manual_voucher_details_status_check,
  ADD CONSTRAINT manual_voucher_details_status_check
    CHECK(status IN('draft','finalized')),
  ADD CONSTRAINT manual_voucher_details_finalized_by_fkey
    FOREIGN KEY(finalized_by) REFERENCES public.profiles(id) ON DELETE RESTRICT,
  ADD CONSTRAINT manual_voucher_details_finalization_metadata_check
    CHECK(
      (status='draft' AND finalized_at IS NULL AND finalized_by IS NULL)
      OR (status='finalized' AND finalized_at IS NOT NULL AND finalized_by IS NOT NULL)
    );

CREATE TABLE public.manual_vehicle_chakkar_settlements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  manual_voucher_id uuid NOT NULL,
  voucher_id bigint NOT NULL,
  adda_id uuid NOT NULL,
  vehicle_id uuid NOT NULL,
  driver_id uuid,
  settlement_date date NOT NULL,
  chakkar_days integer NOT NULL,
  total_freight numeric(14,2) NOT NULL,
  regular_expense_total numeric(14,2) NOT NULL DEFAULT 0,
  periodic_expense_total numeric(14,2) NOT NULL DEFAULT 0,
  total_expense_amount numeric(14,2) NOT NULL,
  net_vehicle_amount numeric(14,2) NOT NULL,
  freight_snapshot jsonb NOT NULL,
  expense_snapshot jsonb NOT NULL,
  finalized_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  finalized_by uuid NOT NULL,
  accounting_version integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT manual_vehicle_chakkar_settlements_manual_voucher_fkey
    FOREIGN KEY(manual_voucher_id) REFERENCES public.manual_voucher_details(id) ON DELETE RESTRICT,
  CONSTRAINT manual_vehicle_chakkar_settlements_voucher_fkey
    FOREIGN KEY(voucher_id) REFERENCES public.expenses(id) ON DELETE RESTRICT,
  CONSTRAINT manual_vehicle_chakkar_settlements_adda_fkey
    FOREIGN KEY(adda_id) REFERENCES public.addas(id) ON DELETE RESTRICT,
  CONSTRAINT manual_vehicle_chakkar_settlements_vehicle_adda_fkey
    FOREIGN KEY(vehicle_id,adda_id) REFERENCES public.vehicles(id,adda_id) ON DELETE RESTRICT,
  CONSTRAINT manual_vehicle_chakkar_settlements_driver_adda_fkey
    FOREIGN KEY(driver_id,adda_id) REFERENCES public.drivers(id,adda_id) ON DELETE RESTRICT,
  CONSTRAINT manual_vehicle_chakkar_settlements_finalized_by_fkey
    FOREIGN KEY(finalized_by) REFERENCES public.profiles(id) ON DELETE RESTRICT,
  CONSTRAINT manual_vehicle_chakkar_settlements_voucher_key UNIQUE(voucher_id),
  CONSTRAINT manual_vehicle_chakkar_settlements_manual_key UNIQUE(manual_voucher_id),
  CONSTRAINT manual_vehicle_chakkar_settlements_id_adda_vehicle_key UNIQUE(id,adda_id,vehicle_id),
  CONSTRAINT manual_vehicle_chakkar_settlements_days_check CHECK(chakkar_days>0),
  CONSTRAINT manual_vehicle_chakkar_settlements_amounts_check CHECK(
    total_freight>0
    AND regular_expense_total>=0
    AND periodic_expense_total=0
    AND total_expense_amount=regular_expense_total+periodic_expense_total
    AND net_vehicle_amount=total_freight-total_expense_amount
    AND total_freight::text NOT IN('NaN','Infinity','-Infinity')
    AND regular_expense_total::text NOT IN('NaN','Infinity','-Infinity')
    AND total_expense_amount::text NOT IN('NaN','Infinity','-Infinity')
    AND net_vehicle_amount::text NOT IN('NaN','Infinity','-Infinity')
  ),
  CONSTRAINT manual_vehicle_chakkar_settlements_accounting_version_check CHECK(accounting_version=1),
  CONSTRAINT manual_vehicle_chakkar_settlements_snapshot_check CHECK(
    pg_catalog.jsonb_typeof(freight_snapshot)='array'
    AND pg_catalog.jsonb_typeof(expense_snapshot)='array'
  )
);

CREATE INDEX manual_vehicle_chakkar_settlements_vehicle_date_idx
  ON public.manual_vehicle_chakkar_settlements(adda_id,vehicle_id,settlement_date,id);

ALTER TABLE public.owner_gari_account_transactions
  ADD COLUMN source_manual_settlement_id uuid,
  DROP CONSTRAINT owner_gari_transactions_type_check,
  DROP CONSTRAINT owner_gari_transactions_commission_source_check,
  ADD CONSTRAINT owner_gari_transactions_manual_settlement_fkey
    FOREIGN KEY(source_manual_settlement_id,adda_id,vehicle_id)
    REFERENCES public.manual_vehicle_chakkar_settlements(id,adda_id,vehicle_id) ON DELETE RESTRICT,
  ADD CONSTRAINT owner_gari_transactions_type_check CHECK(transaction_type IN(
    'opening_seed','chakkar_net_credit','owner_withdrawal','gari_withdrawal',
    'monthly_adda_commission','monthly_adda_commission_reversal',
    'monthly_adda_commission_reissue','monthly_adda_commission_adjustment_increase',
    'monthly_adda_commission_adjustment_decrease',
    'monthly_adda_commission_correction_reversal_credit',
    'monthly_adda_commission_correction_reversal_debit',
    'adjustment_credit','adjustment_debit','voucher_adjustment_expense',
    'manual_chakkar_net'
  )),
  ADD CONSTRAINT owner_gari_transactions_commission_source_check CHECK(
    (transaction_type='chakkar_net_credit'
      AND source_settlement_id IS NOT NULL AND source_adjustment_id IS NULL
      AND source_commission_event_id IS NULL AND source_manual_settlement_id IS NULL)
    OR (transaction_type='voucher_adjustment_expense'
      AND source_settlement_id IS NULL AND source_adjustment_id IS NOT NULL
      AND source_commission_event_id IS NULL AND source_manual_settlement_id IS NULL)
    OR (transaction_type='manual_chakkar_net'
      AND source_settlement_id IS NULL AND source_adjustment_id IS NULL
      AND source_commission_event_id IS NULL AND source_manual_settlement_id IS NOT NULL)
    OR (transaction_type IN(
      'monthly_adda_commission','monthly_adda_commission_reversal',
      'monthly_adda_commission_reissue','monthly_adda_commission_adjustment_increase',
      'monthly_adda_commission_adjustment_decrease',
      'monthly_adda_commission_correction_reversal_credit',
      'monthly_adda_commission_correction_reversal_debit'
    ) AND source_settlement_id IS NULL AND source_adjustment_id IS NULL
      AND source_commission_event_id IS NOT NULL AND source_manual_settlement_id IS NULL)
    OR (transaction_type NOT IN(
      'chakkar_net_credit','voucher_adjustment_expense','manual_chakkar_net',
      'monthly_adda_commission','monthly_adda_commission_reversal',
      'monthly_adda_commission_reissue','monthly_adda_commission_adjustment_increase',
      'monthly_adda_commission_adjustment_decrease',
      'monthly_adda_commission_correction_reversal_credit',
      'monthly_adda_commission_correction_reversal_debit'
    ) AND source_settlement_id IS NULL AND source_adjustment_id IS NULL
      AND source_commission_event_id IS NULL AND source_manual_settlement_id IS NULL)
  ),
  ADD CONSTRAINT owner_gari_transactions_manual_amount_check CHECK(
    transaction_type<>'manual_chakkar_net'
    OR amount::text NOT IN('NaN','Infinity','-Infinity')
  );

CREATE UNIQUE INDEX owner_gari_transactions_manual_settlement_uidx
  ON public.owner_gari_account_transactions(source_manual_settlement_id)
  WHERE source_manual_settlement_id IS NOT NULL;

ALTER TABLE public.manual_vehicle_chakkar_settlements ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.manual_vehicle_chakkar_settlements FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.manual_vehicle_chakkar_settlements TO authenticated;
CREATE POLICY manual_vehicle_chakkar_settlements_tenant_select
  ON public.manual_vehicle_chakkar_settlements FOR SELECT TO authenticated
  USING((SELECT public.is_super_admin()) OR adda_id=(SELECT public.current_user_adda_id()));

CREATE FUNCTION public.ut_guard_manual_voucher_phase2a()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_detail public.manual_voucher_details%ROWTYPE;
  v_manual boolean:=false;
BEGIN
  IF TG_TABLE_NAME='expenses' THEN
    IF TG_OP='DELETE' THEN
      v_manual:=OLD.voucher_source='manual';
      IF NOT v_manual THEN RETURN OLD; END IF;
      SELECT detail.* INTO v_detail FROM public.manual_voucher_details detail
      WHERE detail.voucher_id=OLD.id FOR KEY SHARE;
      IF NOT FOUND
         AND coalesce(pg_catalog.current_setting('ut.manual_voucher_sync',true),'')='on' THEN
        RETURN OLD;
      END IF;
    ELSE
      v_manual:=NEW.voucher_source='manual' OR (TG_OP='UPDATE' AND OLD.voucher_source='manual');
      IF NOT v_manual THEN RETURN NEW; END IF;
      IF NEW.voucher_source IS DISTINCT FROM 'manual' THEN
        RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_SOURCE_IS_IMMUTABLE';
      END IF;
      SELECT detail.* INTO v_detail FROM public.manual_voucher_details detail
      WHERE detail.voucher_id=NEW.id FOR KEY SHARE;
    END IF;
    IF NOT FOUND OR v_detail.status<>'draft'
       OR coalesce(pg_catalog.current_setting('ut.manual_voucher_sync',true),'')<>'on' THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_DRAFT_RPC_REQUIRED';
    END IF;
    RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
  ELSIF TG_TABLE_NAME='manual_voucher_details' THEN
    IF TG_OP='INSERT' THEN
      IF NEW.status<>'draft' OR NEW.finalized_at IS NOT NULL OR NEW.finalized_by IS NOT NULL
         OR coalesce(pg_catalog.current_setting('ut.manual_voucher_sync',true),'')<>'on' THEN
        RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_DRAFT_RPC_REQUIRED';
      END IF;
      RETURN NEW;
    ELSIF TG_OP='DELETE' THEN
      IF OLD.status<>'draft'
         OR coalesce(pg_catalog.current_setting('ut.manual_voucher_sync',true),'')<>'on' THEN
        RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='FINALIZED_MANUAL_VOUCHER_IS_IMMUTABLE';
      END IF;
      RETURN OLD;
    END IF;
    IF OLD.status='finalized' THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='FINALIZED_MANUAL_VOUCHER_IS_IMMUTABLE';
    END IF;
    IF coalesce(pg_catalog.current_setting('ut.manual_voucher_sync',true),'')='on'
       AND NEW.status='draft'
       AND NEW.finalized_at IS NULL AND NEW.finalized_by IS NULL THEN
      RETURN NEW;
    END IF;
    IF coalesce(pg_catalog.current_setting('ut.manual_voucher_finalizing',true),'')='on'
       AND OLD.status='draft' AND NEW.status='finalized'
       AND NEW.id IS NOT DISTINCT FROM OLD.id
       AND NEW.voucher_id IS NOT DISTINCT FROM OLD.voucher_id
       AND NEW.adda_id IS NOT DISTINCT FROM OLD.adda_id
       AND NEW.vehicle_id IS NOT DISTINCT FROM OLD.vehicle_id
       AND NEW.driver_id IS NOT DISTINCT FROM OLD.driver_id
       AND NEW.voucher_date IS NOT DISTINCT FROM OLD.voucher_date
       AND NEW.chakkar_days IS NOT DISTINCT FROM OLD.chakkar_days
       AND NEW.remarks IS NOT DISTINCT FROM OLD.remarks
       AND NEW.created_by IS NOT DISTINCT FROM OLD.created_by
       AND NEW.created_at IS NOT DISTINCT FROM OLD.created_at
       AND NEW.finalized_at IS NOT NULL AND NEW.finalized_by=auth.uid() THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_DRAFT_RPC_REQUIRED';
  ELSIF TG_TABLE_NAME='manual_voucher_freight_items' THEN
    SELECT detail.* INTO v_detail
    FROM public.manual_voucher_details detail
    WHERE detail.id=CASE WHEN TG_OP='DELETE' THEN OLD.manual_voucher_id ELSE NEW.manual_voucher_id END
    FOR KEY SHARE;
    IF NOT FOUND OR v_detail.status<>'draft'
       OR coalesce(pg_catalog.current_setting('ut.manual_voucher_sync',true),'')<>'on' THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_DRAFT_RPC_REQUIRED';
    END IF;
    IF TG_OP='UPDATE' AND OLD.manual_voucher_id IS DISTINCT FROM NEW.manual_voucher_id THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_FREIGHT_OWNERSHIP_IMMUTABLE';
    END IF;
    RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
  ELSIF TG_TABLE_NAME='manual_vehicle_chakkar_settlements' THEN
    IF TG_OP<>'INSERT'
       OR coalesce(pg_catalog.current_setting('ut.manual_voucher_finalizing',true),'')<>'on' THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_SETTLEMENT_APPEND_ONLY';
    END IF;
    SELECT detail.* INTO v_detail
    FROM public.manual_voucher_details detail
    WHERE detail.id=NEW.manual_voucher_id AND detail.voucher_id=NEW.voucher_id
      AND detail.adda_id=NEW.adda_id AND detail.vehicle_id=NEW.vehicle_id
      AND detail.driver_id IS NOT DISTINCT FROM NEW.driver_id
      AND detail.voucher_date=NEW.settlement_date AND detail.chakkar_days=NEW.chakkar_days
      AND detail.status='draft'
    FOR KEY SHARE;
    IF NOT FOUND OR NOT EXISTS(
      SELECT 1 FROM public.expenses voucher
      WHERE voucher.id=NEW.voucher_id AND voucher.voucher_source='manual'
        AND voucher.loading_id IS NULL AND voucher.movement_group_id IS NULL
        AND voucher.archived_at IS NULL
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_SETTLEMENT_CONTEXT_MISMATCH';
    END IF;
    RETURN NEW;
  END IF;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END;
$function$;

CREATE TRIGGER expenses_manual_voucher_phase2a_guard
BEFORE UPDATE OR DELETE ON public.expenses
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_manual_voucher_phase2a();
CREATE TRIGGER manual_voucher_details_phase2a_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.manual_voucher_details
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_manual_voucher_phase2a();
CREATE TRIGGER manual_voucher_freight_items_phase2a_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.manual_voucher_freight_items
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_manual_voucher_phase2a();
CREATE TRIGGER manual_vehicle_chakkar_settlements_append_only
BEFORE INSERT OR UPDATE OR DELETE ON public.manual_vehicle_chakkar_settlements
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_manual_voucher_phase2a();

CREATE OR REPLACE FUNCTION public.ut_protect_manual_voucher_expense_item()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_parent_source text;
  v_status text;
  v_expense_id bigint;
BEGIN
  IF TG_OP IN('UPDATE','DELETE') THEN
    SELECT voucher.voucher_source,detail.status
    INTO v_parent_source,v_status
    FROM public.expenses voucher
    LEFT JOIN public.manual_voucher_details detail ON detail.voucher_id=voucher.id
    WHERE voucher.id=OLD.expense_id;
    IF v_parent_source='manual' AND (
      v_status IS DISTINCT FROM 'draft'
      OR coalesce(pg_catalog.current_setting('ut.manual_voucher_expense_sync',true),'')<>'on'
    ) THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_EXPENSE_RPC_REQUIRED';
    END IF;
  END IF;
  IF TG_OP IN('INSERT','UPDATE') THEN
    v_expense_id:=NEW.expense_id;
    SELECT voucher.voucher_source,detail.status
    INTO v_parent_source,v_status
    FROM public.expenses voucher
    LEFT JOIN public.manual_voucher_details detail ON detail.voucher_id=voucher.id
    WHERE voucher.id=v_expense_id;
    IF v_parent_source='manual' AND (
      v_status IS DISTINCT FROM 'draft'
      OR coalesce(pg_catalog.current_setting('ut.manual_voucher_expense_sync',true),'')<>'on'
    ) THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_EXPENSE_RPC_REQUIRED';
    END IF;
    RETURN NEW;
  END IF;
  RETURN OLD;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ut_sync_voucher_item_cashbook_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_old_source text;
  v_new_source text;
BEGIN
  IF TG_OP IN('INSERT','UPDATE') AND (
    NEW.amount IS NULL OR NEW.amount::text IN('NaN','Infinity','-Infinity') OR NEW.amount<=0
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='Voucher item amount must be greater than zero';
  END IF;

  IF TG_OP IN('UPDATE','DELETE') THEN
    SELECT voucher.voucher_source INTO v_old_source
    FROM public.expenses voucher WHERE voucher.id=OLD.expense_id;
  END IF;
  IF TG_OP IN('INSERT','UPDATE') THEN
    SELECT voucher.voucher_source INTO v_new_source
    FROM public.expenses voucher WHERE voucher.id=NEW.expense_id;
  END IF;

  IF TG_OP='UPDATE' AND NEW.expense_id IS DISTINCT FROM OLD.expense_id
     AND v_old_source IS DISTINCT FROM 'manual' THEN
    PERFORM public.ut_sync_voucher_cashbook(OLD.expense_id::text);
  END IF;
  IF TG_OP='DELETE' THEN
    IF v_old_source IS DISTINCT FROM 'manual' THEN
      PERFORM public.ut_sync_voucher_cashbook(OLD.expense_id::text);
    END IF;
    RETURN OLD;
  END IF;
  IF v_new_source IS DISTINCT FROM 'manual' THEN
    PERFORM public.ut_sync_voucher_cashbook(NEW.expense_id::text);
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ut_guard_manual_owner_gari_projection()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_settlement public.manual_vehicle_chakkar_settlements%ROWTYPE;
  v_detail_status text;
BEGIN
  IF TG_OP='UPDATE' AND (OLD.transaction_type='manual_chakkar_net' OR NEW.transaction_type='manual_chakkar_net')
     OR TG_OP='DELETE' AND OLD.transaction_type='manual_chakkar_net' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_OWNER_GARI_PROJECTION_APPEND_ONLY';
  END IF;
  IF TG_OP='INSERT' AND NEW.transaction_type='manual_chakkar_net' THEN
    IF coalesce(pg_catalog.current_setting('ut.manual_voucher_finalizing',true),'')<>'on' THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_OWNER_GARI_PROJECTION_RPC_REQUIRED';
    END IF;
    SELECT settlement.* INTO v_settlement
    FROM public.manual_vehicle_chakkar_settlements settlement
    WHERE settlement.id=NEW.source_manual_settlement_id
      AND settlement.adda_id=NEW.adda_id AND settlement.vehicle_id=NEW.vehicle_id
    FOR KEY SHARE;
    IF NOT FOUND OR NEW.amount IS DISTINCT FROM v_settlement.net_vehicle_amount
       OR NEW.transaction_date IS DISTINCT FROM v_settlement.settlement_date
       OR NEW.source_settlement_id IS NOT NULL OR NEW.source_adjustment_id IS NOT NULL
       OR NEW.source_commission_event_id IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_OWNER_GARI_PROJECTION_MISMATCH';
    END IF;
    SELECT detail.status INTO v_detail_status
    FROM public.manual_voucher_details detail
    WHERE detail.id=v_settlement.manual_voucher_id
      AND detail.voucher_id=v_settlement.voucher_id
      AND detail.adda_id=NEW.adda_id AND detail.vehicle_id=NEW.vehicle_id
    FOR KEY SHARE;
    IF NOT FOUND OR v_detail_status<>'finalized' THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_OWNER_GARI_SOURCE_NOT_FINALIZED';
    END IF;
  END IF;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END;
$function$;

CREATE TRIGGER owner_gari_manual_projection_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.owner_gari_account_transactions
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_manual_owner_gari_projection();

CREATE OR REPLACE FUNCTION public.save_manual_voucher(
  p_voucher_id bigint,p_expense_no text,p_voucher_date date,p_vehicle_id uuid,
  p_driver_id uuid,p_chakkar_days integer,p_remarks text,p_freight_items jsonb
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  actor_id uuid:=auth.uid();
  actor_role text;
  context_adda_id uuid;
  driver_adda_id uuid;
  saved_voucher_id bigint;
  manual_detail_id uuid;
  manual_detail_adda_id uuid;
  manual_detail_status text;
  line_row jsonb;
  freight_type_value text;
  line_amount numeric;
  sequence_value integer;
  line_count integer:=0;
  outbound_count integer:=0;
  return_count integer:=0;
  expense_row record;
BEGIN
  IF actor_id IS NULL OR NOT EXISTS(
    SELECT 1 FROM public.profiles profile WHERE profile.id=actor_id AND profile.is_active=true
  ) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_NOT_AUTHORIZED'; END IF;
  actor_role:=public.current_user_role();
  IF actor_role IS NULL OR actor_role NOT IN('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ROLE_REQUIRED';
  END IF;
  IF NULLIF(pg_catalog.btrim(p_expense_no),'') IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_NUMBER_REQUIRED';
  END IF;
  IF p_voucher_date IS NULL OR p_vehicle_id IS NULL OR p_chakkar_days IS NULL OR p_chakkar_days<=0 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_REQUIRED_FIELDS_INVALID';
  END IF;
  IF p_freight_items IS NULL OR pg_catalog.jsonb_typeof(p_freight_items)<>'array'
     OR pg_catalog.jsonb_array_length(p_freight_items)=0 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_FREIGHT_REQUIRED';
  END IF;
  SELECT vehicle.adda_id INTO context_adda_id
  FROM public.vehicles vehicle WHERE vehicle.id=p_vehicle_id FOR KEY SHARE;
  IF NOT FOUND OR context_adda_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='MANUAL_VOUCHER_VEHICLE_NOT_FOUND';
  END IF;
  IF NOT public.is_super_admin() AND context_adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_VEHICLE_ADDA_MISMATCH';
  END IF;
  IF p_driver_id IS NOT NULL THEN
    SELECT driver.adda_id INTO driver_adda_id FROM public.drivers driver
    WHERE driver.id=p_driver_id FOR KEY SHARE;
    IF NOT FOUND OR driver_adda_id IS DISTINCT FROM context_adda_id THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_DRIVER_ADDA_MISMATCH';
    END IF;
  END IF;
  FOR line_row IN SELECT value FROM pg_catalog.jsonb_array_elements(p_freight_items) AS lines(value) LOOP
    IF pg_catalog.jsonb_typeof(line_row)<>'object' THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_FREIGHT_ROW_INVALID';
    END IF;
    freight_type_value:=line_row->>'freight_type';
    IF coalesce(line_row->>'amount','') !~ '^[0-9]+([.][0-9]{1,2})?$' THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_FREIGHT_AMOUNT_INVALID';
    END IF;
    line_amount:=(line_row->>'amount')::numeric;
    IF line_amount<=0 OR line_amount::text IN('NaN','Infinity','-Infinity') THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_FREIGHT_AMOUNT_INVALID';
    END IF;
    IF coalesce(line_row->>'sequence_no','') !~ '^[1-9][0-9]*$' THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_FREIGHT_SEQUENCE_INVALID';
    END IF;
    sequence_value:=(line_row->>'sequence_no')::integer;
    IF freight_type_value NOT IN('outbound','local','return') THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_FREIGHT_TYPE_INVALID';
    END IF;
    line_count:=line_count+1;
    IF freight_type_value='outbound' THEN outbound_count:=outbound_count+1; END IF;
    IF freight_type_value='return' THEN return_count:=return_count+1; END IF;
  END LOOP;
  IF outbound_count>1 OR return_count>1 THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_FREIGHT_CARDINALITY_INVALID';
  END IF;
  IF p_voucher_id IS NOT NULL THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('manual-voucher:'||p_voucher_id::text,0));
    SELECT voucher.id,voucher.voucher_source,voucher.archived_at,voucher.loading_id,voucher.movement_group_id
    INTO expense_row FROM public.expenses voucher WHERE voucher.id=p_voucher_id FOR UPDATE;
    IF NOT FOUND OR expense_row.voucher_source IS DISTINCT FROM 'manual' THEN
      RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='MANUAL_VOUCHER_NOT_FOUND';
    END IF;
    IF expense_row.archived_at IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ARCHIVED_VOUCHER_IS_READ_ONLY'; END IF;
    IF expense_row.loading_id IS NOT NULL OR expense_row.movement_group_id IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_CONTEXT_CONFLICT';
    END IF;
    SELECT detail.id,detail.adda_id,detail.status
    INTO manual_detail_id,manual_detail_adda_id,manual_detail_status
    FROM public.manual_voucher_details detail WHERE detail.voucher_id=p_voucher_id FOR UPDATE;
    IF NOT FOUND OR manual_detail_status<>'draft' THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_DRAFT_ONLY';
    END IF;
    IF manual_detail_adda_id IS DISTINCT FROM context_adda_id THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_ADDA_IS_IMMUTABLE';
    END IF;
    IF EXISTS(SELECT 1 FROM public.vehicle_chakkar_settlements settlement WHERE settlement.voucher_id=p_voucher_id)
       OR EXISTS(SELECT 1 FROM public.manual_vehicle_chakkar_settlements settlement WHERE settlement.voucher_id=p_voucher_id)
       OR EXISTS(SELECT 1 FROM public.owner_gari_account_transactions transaction_row
         WHERE transaction_row.source_manual_settlement_id IS NOT NULL
           AND transaction_row.source_manual_settlement_id IN(
             SELECT settlement.id FROM public.manual_vehicle_chakkar_settlements settlement WHERE settlement.voucher_id=p_voucher_id
           ))
       OR EXISTS(SELECT 1 FROM public.diesel_entries diesel WHERE diesel.expense_id=p_voucher_id)
       OR EXISTS(SELECT 1 FROM public.voucher_loadings link WHERE link.voucher_id=p_voucher_id)
       OR EXISTS(SELECT 1 FROM public.voucher_workshop_entries link WHERE link.voucher_id=p_voucher_id)
       OR EXISTS(SELECT 1 FROM public.voucher_oil_entries link WHERE link.voucher_id=p_voucher_id)
       OR EXISTS(SELECT 1 FROM public.voucher_tyre_entries link WHERE link.voucher_id=p_voucher_id)
       OR EXISTS(SELECT 1 FROM public.voucher_driver_earnings link WHERE link.voucher_id=p_voucher_id)
       OR EXISTS(SELECT 1 FROM public.cashbook_entries cashbook
         WHERE cashbook.reference_type='voucher' AND cashbook.reference_id=p_voucher_id::text)
       OR EXISTS(SELECT 1 FROM public.expense_items item WHERE item.expense_id=p_voucher_id
         AND (item.expense_class IS DISTINCT FROM 'regular_trip' OR item.expense_type NOT IN(
           'Toll Tax','Food','Labour','Maintenance','Police','Parking','Other',
           'Driver Kharcha','Munshiana','Loading / Unloading'
         ) OR item.amount IS NULL OR item.amount<=0 OR item.amount::text IN('NaN','Infinity','-Infinity'))) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_HAS_UNSAFE_ACCOUNTING_DEPENDENCIES';
    END IF;
    saved_voucher_id:=p_voucher_id;
  END IF;
  PERFORM pg_catalog.set_config('ut.manual_voucher_sync','on',true);
  PERFORM pg_catalog.set_config('ut.manual_voucher_adda_id',context_adda_id::text,true);
  PERFORM pg_catalog.set_config('ut.manual_voucher_vehicle_id',p_vehicle_id::text,true);
  IF p_voucher_id IS NULL THEN
    INSERT INTO public.expenses(expense_no,expense_date,start_date,end_date,loading_id,movement_group_id,description,voucher_source)
    VALUES(pg_catalog.btrim(p_expense_no),p_voucher_date,p_voucher_date,p_voucher_date,NULL,NULL,NULLIF(pg_catalog.btrim(p_remarks),''),'manual')
    RETURNING id INTO saved_voucher_id;
    INSERT INTO public.manual_voucher_details(voucher_id,adda_id,vehicle_id,driver_id,voucher_date,chakkar_days,remarks,status,created_by)
    VALUES(saved_voucher_id,context_adda_id,p_vehicle_id,p_driver_id,p_voucher_date,p_chakkar_days,
      NULLIF(pg_catalog.btrim(p_remarks),''),'draft',actor_id)
    RETURNING id INTO manual_detail_id;
  ELSE
    UPDATE public.expenses voucher SET expense_no=pg_catalog.btrim(p_expense_no),expense_date=p_voucher_date,
      start_date=p_voucher_date,end_date=p_voucher_date,loading_id=NULL,movement_group_id=NULL,
      description=NULLIF(pg_catalog.btrim(p_remarks),''),voucher_source='manual'
    WHERE voucher.id=saved_voucher_id;
    UPDATE public.manual_voucher_details detail SET vehicle_id=p_vehicle_id,driver_id=p_driver_id,
      voucher_date=p_voucher_date,chakkar_days=p_chakkar_days,remarks=NULLIF(pg_catalog.btrim(p_remarks),''),
      updated_at=pg_catalog.now()
    WHERE detail.id=manual_detail_id AND detail.status='draft';
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_DETAIL_UPDATE_FAILED'; END IF;
    DELETE FROM public.manual_voucher_freight_items item WHERE item.manual_voucher_id=manual_detail_id;
  END IF;
  FOR line_row IN SELECT value FROM pg_catalog.jsonb_array_elements(p_freight_items) AS lines(value) LOOP
    INSERT INTO public.manual_voucher_freight_items(manual_voucher_id,adda_id,freight_type,amount,description,sequence_no)
    VALUES(manual_detail_id,context_adda_id,line_row->>'freight_type',(line_row->>'amount')::numeric,
      NULLIF(pg_catalog.btrim(line_row->>'description'),''),(line_row->>'sequence_no')::integer);
  END LOOP;
  RETURN saved_voucher_id;
END;
$function$;

CREATE FUNCTION public.save_manual_voucher_expense_items(
  p_voucher_id bigint,
  p_items jsonb
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  actor_id uuid:=auth.uid();
  voucher_row public.expenses%ROWTYPE;
  detail_row public.manual_voucher_details%ROWTYPE;
  item_row jsonb;
  item_type text;
  item_amount numeric;
  item_count integer:=0;
BEGIN
  IF actor_id IS NULL OR NOT EXISTS(
    SELECT 1 FROM public.profiles profile WHERE profile.id=actor_id AND profile.is_active=true
  ) OR public.current_user_role() NOT IN('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_EXPENSE_NOT_AUTHORIZED';
  END IF;
  IF p_voucher_id IS NULL OR p_items IS NULL OR pg_catalog.jsonb_typeof(p_items)<>'array'
     OR pg_catalog.jsonb_array_length(p_items)>100 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_EXPENSE_PAYLOAD_INVALID';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('manual-voucher:'||p_voucher_id::text,0));
  SELECT voucher.* INTO voucher_row FROM public.expenses voucher
  WHERE voucher.id=p_voucher_id FOR UPDATE;
  IF NOT FOUND OR voucher_row.voucher_source IS DISTINCT FROM 'manual' THEN
    RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='MANUAL_VOUCHER_NOT_FOUND';
  END IF;
  IF voucher_row.archived_at IS NOT NULL OR voucher_row.loading_id IS NOT NULL
     OR voucher_row.movement_group_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_CONTEXT_INVALID';
  END IF;
  SELECT detail.* INTO detail_row FROM public.manual_voucher_details detail
  WHERE detail.voucher_id=p_voucher_id FOR UPDATE;
  IF NOT FOUND OR detail_row.status<>'draft' THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='FINALIZED_MANUAL_VOUCHER_IS_IMMUTABLE';
  END IF;
  IF NOT public.is_super_admin() AND detail_row.adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ADDA_MISMATCH';
  END IF;
  IF EXISTS(SELECT 1 FROM public.manual_vehicle_chakkar_settlements settlement
    WHERE settlement.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.vehicle_chakkar_settlements settlement
       WHERE settlement.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.diesel_entries diesel WHERE diesel.expense_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.voucher_loadings link WHERE link.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.voucher_workshop_entries link WHERE link.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.voucher_oil_entries link WHERE link.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.voucher_tyre_entries link WHERE link.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.voucher_driver_earnings link WHERE link.voucher_id=p_voucher_id) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_SOURCE_LINKS_UNSUPPORTED';
  END IF;
  FOR item_row IN SELECT value FROM pg_catalog.jsonb_array_elements(p_items) AS items(value) LOOP
    IF pg_catalog.jsonb_typeof(item_row)<>'object'
       OR item_row->>'expense_class'<>'regular_trip' THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_EXPENSE_CLASS_UNSUPPORTED';
    END IF;
    item_type:=item_row->>'expense_type';
    IF item_type IS NULL OR item_type NOT IN(
      'Toll Tax','Food','Labour','Maintenance','Police','Parking','Other',
      'Driver Kharcha','Munshiana','Loading / Unloading'
    ) THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_EXPENSE_TYPE_UNSUPPORTED';
    END IF;
    IF pg_catalog.jsonb_typeof(item_row->'amount') NOT IN('number','string')
       OR coalesce(item_row->>'amount','') !~ '^[0-9]+([.][0-9]{1,2})?$' THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_EXPENSE_AMOUNT_INVALID';
    END IF;
    item_amount:=(item_row->>'amount')::numeric;
    IF item_amount<=0 OR item_amount::text IN('NaN','Infinity','-Infinity')
       OR item_amount<>pg_catalog.round(item_amount,2) THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_EXPENSE_AMOUNT_INVALID';
    END IF;
    item_count:=item_count+1;
  END LOOP;

  PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true);
  DELETE FROM public.expense_items item WHERE item.expense_id=p_voucher_id;
  FOR item_row IN SELECT value FROM pg_catalog.jsonb_array_elements(p_items) AS items(value) LOOP
    INSERT INTO public.expense_items(expense_id,expense_class,expense_type,amount,payment_method,remarks)
    VALUES(
      p_voucher_id,'regular_trip',item_row->>'expense_type',(item_row->>'amount')::numeric,
      'Not Paid',NULLIF(pg_catalog.btrim(item_row->>'remarks'),'')
    );
  END LOOP;
  RETURN item_count;
END;
$function$;

CREATE FUNCTION public.save_manual_voucher_phase2(
  p_voucher_id bigint,p_expense_no text,p_voucher_date date,p_vehicle_id uuid,
  p_driver_id uuid,p_chakkar_days integer,p_remarks text,p_freight_items jsonb,p_expense_items jsonb
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  saved_voucher_id bigint;
BEGIN
  saved_voucher_id:=public.save_manual_voucher(
    p_voucher_id,p_expense_no,p_voucher_date,p_vehicle_id,p_driver_id,
    p_chakkar_days,p_remarks,p_freight_items
  );
  PERFORM public.save_manual_voucher_expense_items(saved_voucher_id,p_expense_items);
  RETURN saved_voucher_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_manual_voucher_draft(p_voucher_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  actor_id uuid:=auth.uid();
  voucher_row public.expenses%ROWTYPE;
  detail_row public.manual_voucher_details%ROWTYPE;
  account_transaction_count integer;
BEGIN
  IF actor_id IS NULL OR NOT EXISTS(
    SELECT 1 FROM public.profiles profile WHERE profile.id=actor_id AND profile.is_active=true
  ) OR public.current_user_role() NOT IN('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_DELETE_NOT_AUTHORIZED';
  END IF;
  IF p_voucher_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_ID_REQUIRED';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('manual-voucher:'||p_voucher_id::text,0));
  SELECT voucher.* INTO voucher_row FROM public.expenses voucher WHERE voucher.id=p_voucher_id FOR UPDATE;
  IF NOT FOUND OR voucher_row.voucher_source IS DISTINCT FROM 'manual' THEN
    RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='MANUAL_VOUCHER_NOT_FOUND';
  END IF;
  SELECT detail.* INTO detail_row FROM public.manual_voucher_details detail
  WHERE detail.voucher_id=p_voucher_id FOR UPDATE;
  IF NOT FOUND OR detail_row.status<>'draft' THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_DRAFT_ONLY';
  END IF;
  IF voucher_row.archived_at IS NOT NULL OR voucher_row.loading_id IS NOT NULL
     OR voucher_row.movement_group_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_CONTEXT_CONFLICT';
  END IF;
  IF NOT public.is_super_admin() AND detail_row.adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ADDA_MISMATCH';
  END IF;
  SELECT pg_catalog.count(*)::integer INTO account_transaction_count
  FROM public.owner_gari_account_transactions transaction_row
  WHERE transaction_row.source_manual_settlement_id IN(
    SELECT settlement.id FROM public.manual_vehicle_chakkar_settlements settlement
    WHERE settlement.voucher_id=p_voucher_id
  );
  IF EXISTS(SELECT 1 FROM public.manual_vehicle_chakkar_settlements settlement WHERE settlement.voucher_id=p_voucher_id)
     OR account_transaction_count<>0
     OR EXISTS(SELECT 1 FROM public.vehicle_chakkar_settlements settlement WHERE settlement.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.diesel_entries diesel WHERE diesel.expense_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.voucher_loadings link WHERE link.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.voucher_workshop_entries link WHERE link.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.voucher_oil_entries link WHERE link.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.voucher_tyre_entries link WHERE link.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.voucher_driver_earnings link WHERE link.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.cashbook_entries cashbook
       WHERE cashbook.reference_type='voucher' AND cashbook.reference_id=p_voucher_id::text)
     OR EXISTS(SELECT 1 FROM public.expense_items item WHERE item.expense_id=p_voucher_id
       AND (item.expense_class<>'regular_trip' OR item.expense_type NOT IN(
         'Toll Tax','Food','Labour','Maintenance','Police','Parking','Other',
         'Driver Kharcha','Munshiana','Loading / Unloading'
       ))) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_HAS_UNSAFE_ACCOUNTING_DEPENDENCIES';
  END IF;
  PERFORM pg_catalog.set_config('ut.manual_voucher_sync','on',true);
  PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true);
  PERFORM pg_catalog.set_config('ut.voucher_delete_sync','on',true);
  DELETE FROM public.expense_items item WHERE item.expense_id=p_voucher_id;
  DELETE FROM public.manual_voucher_freight_items item WHERE item.manual_voucher_id=detail_row.id;
  DELETE FROM public.manual_voucher_details detail WHERE detail.id=detail_row.id AND detail.status='draft';
  DELETE FROM public.expenses voucher WHERE voucher.id=p_voucher_id AND voucher.voucher_source='manual';
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='MANUAL_VOUCHER_DELETE_FAILED'; END IF;
END;
$function$;

CREATE FUNCTION public.finalize_manual_voucher(p_voucher_id bigint)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  actor_id uuid:=auth.uid();
  actor_role text;
  voucher_row public.expenses%ROWTYPE;
  detail_row public.manual_voucher_details%ROWTYPE;
  settlement_row public.manual_vehicle_chakkar_settlements%ROWTYPE;
  owner_row public.owner_gari_account_transactions%ROWTYPE;
  owner_account_id uuid;
  freight_total numeric(14,2);
  regular_total numeric(14,2);
  periodic_total numeric(14,2):=0;
  total_expenses numeric(14,2);
  net_amount numeric(14,2);
  freight_snapshot jsonb;
  expense_snapshot jsonb;
  projection_count integer;
BEGIN
  IF actor_id IS NULL OR NOT EXISTS(
    SELECT 1 FROM public.profiles profile WHERE profile.id=actor_id AND profile.is_active=true
  ) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='AUTHENTICATION_REQUIRED'; END IF;
  actor_role:=public.current_user_role();
  IF actor_role IS NULL OR actor_role NOT IN('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_FINALIZE_ROLE_REQUIRED';
  END IF;
  IF p_voucher_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_ID_REQUIRED'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('manual-voucher:'||p_voucher_id::text,0));
  SELECT voucher.* INTO voucher_row FROM public.expenses voucher WHERE voucher.id=p_voucher_id FOR UPDATE;
  IF NOT FOUND OR voucher_row.voucher_source IS DISTINCT FROM 'manual' THEN
    RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='MANUAL_VOUCHER_NOT_FOUND';
  END IF;
  SELECT detail.* INTO detail_row FROM public.manual_voucher_details detail
  WHERE detail.voucher_id=p_voucher_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_DETAIL_MISSING'; END IF;
  IF voucher_row.archived_at IS NOT NULL OR voucher_row.loading_id IS NOT NULL
     OR voucher_row.movement_group_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_CONTEXT_INVALID';
  END IF;
  IF NOT public.is_super_admin() AND detail_row.adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ADDA_MISMATCH';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.vehicles vehicle
    WHERE vehicle.id=detail_row.vehicle_id AND vehicle.adda_id=detail_row.adda_id)
     OR (detail_row.driver_id IS NOT NULL AND NOT EXISTS(
       SELECT 1 FROM public.drivers driver
       WHERE driver.id=detail_row.driver_id AND driver.adda_id=detail_row.adda_id
     )) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_VEHICLE_OR_DRIVER_CONTEXT_INVALID';
  END IF;

  IF detail_row.status='finalized' THEN
    SELECT settlement.* INTO settlement_row FROM public.manual_vehicle_chakkar_settlements settlement
    WHERE settlement.voucher_id=p_voucher_id FOR KEY SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_FINALIZATION_INCOMPLETE'; END IF;
    SELECT pg_catalog.count(*)::integer INTO projection_count
    FROM public.owner_gari_account_transactions transaction_row
    WHERE transaction_row.transaction_type='manual_chakkar_net'
      AND transaction_row.source_manual_settlement_id=settlement_row.id
      AND transaction_row.adda_id=detail_row.adda_id AND transaction_row.vehicle_id=detail_row.vehicle_id
      AND transaction_row.amount=settlement_row.net_vehicle_amount
      AND transaction_row.transaction_date=detail_row.voucher_date;
    IF projection_count<>1 OR EXISTS(
      SELECT 1 FROM public.owner_gari_account_transactions transaction_row
      WHERE transaction_row.source_manual_settlement_id=settlement_row.id
        AND transaction_row.transaction_type<>'manual_chakkar_net'
    ) OR settlement_row.total_freight IS DISTINCT FROM settlement_row.net_vehicle_amount+settlement_row.total_expense_amount THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_FINALIZATION_PROJECTION_CONFLICT';
    END IF;
    RETURN settlement_row.id;
  END IF;
  IF detail_row.status<>'draft' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_STATUS_INVALID'; END IF;
  IF EXISTS(SELECT 1 FROM public.manual_vehicle_chakkar_settlements settlement WHERE settlement.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.owner_gari_account_transactions transaction_row
       WHERE transaction_row.source_manual_settlement_id IS NOT NULL
         AND transaction_row.source_manual_settlement_id IN(
           SELECT settlement.id FROM public.manual_vehicle_chakkar_settlements settlement
           WHERE settlement.voucher_id=p_voucher_id
         )) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_PARTIAL_FINALIZATION_CONFLICT';
  END IF;
  IF EXISTS(SELECT 1 FROM public.vehicle_chakkar_settlements settlement WHERE settlement.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.diesel_entries diesel WHERE diesel.expense_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.voucher_loadings link WHERE link.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.voucher_workshop_entries link WHERE link.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.voucher_oil_entries link WHERE link.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.voucher_tyre_entries link WHERE link.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.voucher_driver_earnings link WHERE link.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.cashbook_entries cashbook
       WHERE cashbook.reference_type='voucher' AND cashbook.reference_id=p_voucher_id::text) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_UNSUPPORTED_ACCOUNTING_DEPENDENCY';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.manual_voucher_freight_items freight
    WHERE freight.manual_voucher_id=detail_row.id AND freight.amount>0) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_FREIGHT_REQUIRED';
  END IF;
  IF EXISTS(SELECT 1 FROM public.manual_voucher_freight_items freight
    WHERE freight.manual_voucher_id=detail_row.id
      AND (freight.amount<=0 OR freight.amount::text IN('NaN','Infinity','-Infinity'))) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_FREIGHT_INVALID';
  END IF;
  IF EXISTS(SELECT 1 FROM public.expense_items item
    WHERE item.expense_id=p_voucher_id AND (
      item.expense_class IS DISTINCT FROM 'regular_trip'
      OR item.expense_type NOT IN(
        'Toll Tax','Food','Labour','Maintenance','Police','Parking','Other',
        'Driver Kharcha','Munshiana','Loading / Unloading'
      )
      OR item.amount IS NULL OR item.amount<=0
      OR item.amount::text IN('NaN','Infinity','-Infinity')
    )) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_EXPENSE_UNSUPPORTED_OR_INVALID';
  END IF;
  SELECT pg_catalog.round(pg_catalog.sum(freight.amount),2)::numeric(14,2),
    coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'freight_type',freight.freight_type,'amount',freight.amount,
      'description',freight.description,'sequence_no',freight.sequence_no
    ) ORDER BY freight.sequence_no), '[]'::jsonb)
  INTO freight_total,freight_snapshot
  FROM public.manual_voucher_freight_items freight
  WHERE freight.manual_voucher_id=detail_row.id;
  SELECT pg_catalog.round(coalesce(pg_catalog.sum(item.amount),0),2)::numeric(14,2),
    coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'expense_class',item.expense_class,'expense_type',item.expense_type,
      'amount',item.amount,'remarks',item.remarks
    ) ORDER BY item.id), '[]'::jsonb)
  INTO regular_total,expense_snapshot
  FROM public.expense_items item WHERE item.expense_id=p_voucher_id;
  periodic_total:=0;
  total_expenses:=regular_total+periodic_total;
  net_amount:=freight_total-total_expenses;
  IF freight_total IS NULL OR freight_total<=0 OR freight_total::text IN('NaN','Infinity','-Infinity')
     OR regular_total IS NULL OR regular_total::text IN('NaN','Infinity','-Infinity')
     OR net_amount::text IN('NaN','Infinity','-Infinity') THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_FINANCIAL_TOTAL_INVALID';
  END IF;

  PERFORM pg_catalog.set_config('ut.manual_voucher_finalizing','on',true);
  INSERT INTO public.manual_vehicle_chakkar_settlements(
    manual_voucher_id,voucher_id,adda_id,vehicle_id,driver_id,settlement_date,chakkar_days,
    total_freight,regular_expense_total,periodic_expense_total,total_expense_amount,
    net_vehicle_amount,freight_snapshot,expense_snapshot,finalized_by
  ) VALUES(
    detail_row.id,p_voucher_id,detail_row.adda_id,detail_row.vehicle_id,detail_row.driver_id,
    detail_row.voucher_date,detail_row.chakkar_days,freight_total,regular_total,periodic_total,
    total_expenses,net_amount,freight_snapshot,expense_snapshot,actor_id
  ) RETURNING * INTO settlement_row;
  UPDATE public.manual_voucher_details detail SET
    status='finalized',finalized_at=settlement_row.finalized_at,finalized_by=actor_id,
    updated_at=settlement_row.finalized_at
  WHERE detail.id=detail_row.id AND detail.status='draft';
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_FINALIZATION_STATE_CHANGED'; END IF;

  INSERT INTO public.owner_gari_accounts(adda_id,vehicle_id,created_by)
  VALUES(detail_row.adda_id,detail_row.vehicle_id,actor_id)
  ON CONFLICT(adda_id,vehicle_id) DO NOTHING;
  SELECT account.id INTO owner_account_id
  FROM public.owner_gari_accounts account
  WHERE account.adda_id=detail_row.adda_id AND account.vehicle_id=detail_row.vehicle_id
  FOR UPDATE;
  IF owner_account_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='OWNER_GARI_ACCOUNT_RESOLUTION_FAILED'; END IF;
  INSERT INTO public.owner_gari_account_transactions(
    account_id,adda_id,vehicle_id,transaction_date,transaction_type,amount,
    source_manual_settlement_id,reference_no,description,created_by
  ) VALUES(
    owner_account_id,detail_row.adda_id,detail_row.vehicle_id,detail_row.voucher_date,
    'manual_chakkar_net',net_amount,settlement_row.id,voucher_row.expense_no,
    'Manual Voucher Chakkar net — '||voucher_row.expense_no,actor_id
  );
  RETURN settlement_row.id;
END;
$function$;

CREATE FUNCTION public.get_owner_gari_account_statement_v4(
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
  v_transactions jsonb;
  v_adda_id uuid;
  v_start date;
  v_end date;
  v_manual_credit numeric;
  v_manual_debit numeric;
  v_allowed_types text[]:=ARRAY[
    'opening_seed','chakkar_net_credit','owner_withdrawal','gari_withdrawal',
    'monthly_adda_commission','monthly_adda_commission_reversal',
    'monthly_adda_commission_reissue','monthly_adda_commission_adjustment_increase',
    'monthly_adda_commission_adjustment_decrease',
    'monthly_adda_commission_correction_reversal_credit',
    'monthly_adda_commission_correction_reversal_debit',
    'adjustment_credit','adjustment_debit','voucher_adjustment_expense','manual_chakkar_net'
  ];
BEGIN
  IF p_transaction_type IS NOT NULL AND NOT(p_transaction_type=ANY(v_allowed_types)) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_OWNER_GARI_TRANSACTION_TYPE';
  END IF;
  v_report:=public.get_owner_gari_account_statement_v3(
    p_vehicle_id,p_month,p_date_from,p_date_to,NULL,p_movement_group_id,p_search
  );
  v_adda_id:=(v_report->'account'->>'adda_id')::uuid;
  v_start:=NULLIF(v_report->'period'->>'date_from','')::date;
  v_end:=NULLIF(v_report->'period'->>'date_to','')::date;
  SELECT coalesce(pg_catalog.sum(transaction_row.amount)
      FILTER(WHERE transaction_row.amount>0),0),
    coalesce(pg_catalog.sum(-transaction_row.amount)
      FILTER(WHERE transaction_row.amount<0),0)
  INTO v_manual_credit,v_manual_debit
  FROM public.owner_gari_account_transactions transaction_row
  WHERE transaction_row.adda_id=v_adda_id AND transaction_row.vehicle_id=p_vehicle_id
    AND transaction_row.transaction_type='manual_chakkar_net'
    AND (v_start IS NULL OR transaction_row.transaction_date>=v_start)
    AND (v_end IS NULL OR transaction_row.transaction_date<=v_end);

  SELECT coalesce(pg_catalog.jsonb_agg(
    row_value.value || CASE WHEN transaction_row.transaction_type='manual_chakkar_net'
      THEN pg_catalog.jsonb_build_object(
        'credit',greatest(transaction_row.amount,0),
        'debit',greatest(-transaction_row.amount,0),
        'source_manual_settlement_id',settlement.id,
        'manual_settlement_id',settlement.id,
        'voucher_id',settlement.voucher_id,
        'return_bilty_id',NULL,
        'movement_group_id',NULL,
        'manual_chakkar_days',settlement.chakkar_days,
        'manual_total_freight',settlement.total_freight
      ) ELSE '{}'::jsonb END
    ORDER BY row_value.ordinality),'[]'::jsonb)
  INTO v_transactions
  FROM pg_catalog.jsonb_array_elements(v_report->'transactions') WITH ORDINALITY
    AS row_value(value,ordinality)
  LEFT JOIN public.owner_gari_account_transactions transaction_row
    ON transaction_row.id=(row_value.value->>'transaction_id')::uuid
   AND transaction_row.adda_id=v_adda_id AND transaction_row.vehicle_id=p_vehicle_id
  LEFT JOIN public.manual_vehicle_chakkar_settlements settlement
    ON settlement.id=transaction_row.source_manual_settlement_id
   AND settlement.adda_id=v_adda_id AND settlement.vehicle_id=p_vehicle_id
  WHERE p_transaction_type IS NULL OR row_value.value->>'transaction_type'=p_transaction_type;

  v_report:=pg_catalog.jsonb_set(v_report,'{transactions}',v_transactions,true);
  v_report:=pg_catalog.jsonb_set(v_report,'{summary}',
    coalesce(v_report->'summary','{}'::jsonb)
      || pg_catalog.jsonb_build_object(
        'total_chakkar_credit',
          coalesce((v_report->'summary'->>'total_chakkar_credit')::numeric,0)+v_manual_credit,
        'total_manual_chakkar_credit',v_manual_credit,
        'total_manual_chakkar_debit',v_manual_debit,
        'total_manual_chakkar_net',v_manual_credit-v_manual_debit
      ),true);
  RETURN v_report;
END;
$function$;

CREATE FUNCTION public.get_vehicle_monthly_hisab_v2(
  p_vehicle_id uuid,p_month date,p_date_from date,p_date_to date
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_report jsonb;
  v_summary jsonb;
  v_breakdown jsonb;
  v_base_rows jsonb;
  v_manual_rows jsonb;
  v_all_rows jsonb;
  v_manual_count bigint;
  v_manual_freight numeric;
  v_manual_expenses numeric;
  v_manual_driver numeric;
  v_manual_other numeric;
  v_adda_id uuid;
  v_use_range boolean:=p_date_from IS NOT NULL OR p_date_to IS NOT NULL;
  v_month_start date;
BEGIN
  v_report:=public.get_vehicle_monthly_hisab(p_vehicle_id,p_month,p_date_from,p_date_to);
  v_adda_id:=(v_report->'vehicle'->>'adda_id')::uuid;
  IF NOT v_use_range AND p_month IS NOT NULL THEN
    v_month_start:=pg_catalog.date_trunc('month',p_month)::date;
  END IF;

  SELECT pg_catalog.count(*)::bigint,
    coalesce(pg_catalog.sum(settlement.total_freight),0),
    coalesce(pg_catalog.sum(settlement.total_expense_amount),0),
    coalesce(pg_catalog.sum(category.driver_total),0),
    coalesce(pg_catalog.sum(category.other_total),0)
  INTO v_manual_count,v_manual_freight,v_manual_expenses,v_manual_driver,v_manual_other
  FROM public.manual_vehicle_chakkar_settlements settlement
  LEFT JOIN LATERAL(
    SELECT coalesce(pg_catalog.sum((expense_line.value->>'amount')::numeric)
      FILTER(WHERE expense_line.value->>'expense_type'='Driver Kharcha'),0) driver_total,
      coalesce(pg_catalog.sum((expense_line.value->>'amount')::numeric)
      FILTER(WHERE expense_line.value->>'expense_type' NOT IN(
        'Fuel','Workshop','Tyre','Oil / Lubricants','Driver Salary','Driver Kharcha'
      )),0) other_total
    FROM pg_catalog.jsonb_array_elements(settlement.expense_snapshot) expense_line(value)
  ) category ON true
  WHERE settlement.adda_id=v_adda_id AND settlement.vehicle_id=p_vehicle_id
    AND ((v_use_range AND (p_date_from IS NULL OR settlement.settlement_date>=p_date_from)
      AND (p_date_to IS NULL OR settlement.settlement_date<=p_date_to))
      OR (NOT v_use_range AND settlement.settlement_date>=v_month_start
        AND settlement.settlement_date<(v_month_start+INTERVAL '1 month')::date));

  SELECT coalesce(pg_catalog.jsonb_agg(json_row.value
      ORDER BY (json_row.value->>'chakkar_date')::date,
        CASE WHEN json_row.value->>'source_type'='manual' THEN 1 ELSE 0 END,
        json_row.value->>'settlement_id'),'[]'::jsonb)
  INTO v_all_rows
  FROM (
    SELECT base_row.value FROM pg_catalog.jsonb_array_elements(v_report->'chakkars') base_row(value)
    UNION ALL
    SELECT pg_catalog.jsonb_build_object(
      'settlement_id',settlement.id,
      'manual_settlement_id',settlement.id,
      'source_type','manual',
      'voucher_type','Manual',
      'movement_group_id',NULL,
      'movement_group_status','Finalized',
      'chakkar_date',settlement.settlement_date,
      'return_bilty_id',NULL,
      'return_bilty_no',NULL,
      'voucher_id',settlement.voucher_id,
      'voucher_no',voucher.expense_no,
      'vehicle_id',settlement.vehicle_id,
      'vehicle_no',vehicle.vehicle_no,
      'driver_id',settlement.driver_id,
      'chakkar_days',settlement.chakkar_days,
      'vehicle_freight',settlement.total_freight,
      'regular_trip_expenses',settlement.regular_expense_total,
      'vehicle_periodic_expenses',settlement.periodic_expense_total,
      'total_expenses',settlement.total_expense_amount,
      'net_vehicle_amount',settlement.net_vehicle_amount,
      'adjustment_total',0,
      'adjustment_count',0,
      'breakdown_status','RECONCILED',
      'diesel',0,
      'workshop',0,
      'tyre',0,
      'oil',0,
      'driver',category.driver_total,
      'other',category.other_total,
      'accounting_version',settlement.accounting_version,
      'finalized_at',settlement.finalized_at,
      'freight_snapshot',settlement.freight_snapshot,
      'expense_snapshot',settlement.expense_snapshot
    )
    FROM public.manual_vehicle_chakkar_settlements settlement
    JOIN public.expenses voucher ON voucher.id=settlement.voucher_id
    JOIN public.vehicles vehicle ON vehicle.id=settlement.vehicle_id AND vehicle.adda_id=settlement.adda_id
    LEFT JOIN LATERAL(
      SELECT coalesce(pg_catalog.sum((expense_line.value->>'amount')::numeric)
        FILTER(WHERE expense_line.value->>'expense_type'='Driver Kharcha'),0) driver_total,
        coalesce(pg_catalog.sum((expense_line.value->>'amount')::numeric)
        FILTER(WHERE expense_line.value->>'expense_type' NOT IN(
          'Fuel','Workshop','Tyre','Oil / Lubricants','Driver Salary','Driver Kharcha'
        )),0) other_total
      FROM pg_catalog.jsonb_array_elements(settlement.expense_snapshot) expense_line(value)
    ) category ON true
    WHERE settlement.adda_id=v_adda_id AND settlement.vehicle_id=p_vehicle_id
      AND ((v_use_range AND (p_date_from IS NULL OR settlement.settlement_date>=p_date_from)
        AND (p_date_to IS NULL OR settlement.settlement_date<=p_date_to))
        OR (NOT v_use_range AND settlement.settlement_date>=v_month_start
        AND settlement.settlement_date<(v_month_start+INTERVAL '1 month')::date))
  ) json_row(value);

  v_summary:=coalesce(v_report->'summary','{}'::jsonb)
    || pg_catalog.jsonb_build_object(
      'total_chakkar',coalesce((v_report->'summary'->>'total_chakkar')::numeric,0)+v_manual_count,
      'total_vehicle_freight',coalesce((v_report->'summary'->>'total_vehicle_freight')::numeric,0)+v_manual_freight,
      'total_regular_trip_expenses',coalesce((v_report->'summary'->>'total_regular_trip_expenses')::numeric,0)+v_manual_expenses,
      'total_vehicle_periodic_expenses',coalesce((v_report->'summary'->>'total_vehicle_periodic_expenses')::numeric,0),
      'total_expenses',coalesce((v_report->'summary'->>'total_expenses')::numeric,0)+v_manual_expenses,
      'vehicle_monthly_profit',coalesce((v_report->'summary'->>'vehicle_monthly_profit')::numeric,0)+v_manual_freight-v_manual_expenses,
      'manual_chakkar_count',v_manual_count
    );
  v_breakdown:=coalesce(v_report->'expense_breakdown','{}'::jsonb)
    || pg_catalog.jsonb_build_object(
      'regular_trip_expenses',coalesce((v_report->'expense_breakdown'->>'regular_trip_expenses')::numeric,0)+v_manual_expenses,
      'vehicle_periodic_expenses',coalesce((v_report->'expense_breakdown'->>'vehicle_periodic_expenses')::numeric,0),
      'driver',CASE WHEN v_report->'expense_breakdown'->>'driver' IS NULL THEN NULL
        ELSE coalesce((v_report->'expense_breakdown'->>'driver')::numeric,0)+v_manual_driver END,
      'other',CASE WHEN v_report->'expense_breakdown'->>'other' IS NULL THEN NULL
        ELSE coalesce((v_report->'expense_breakdown'->>'other')::numeric,0)+v_manual_other END,
      'manual_expenses',v_manual_expenses
    );
  v_report:=pg_catalog.jsonb_set(v_report,'{summary}',v_summary,true);
  v_report:=pg_catalog.jsonb_set(v_report,'{expense_breakdown}',v_breakdown,true);
  v_report:=pg_catalog.jsonb_set(v_report,'{chakkars}',v_all_rows,true);
  RETURN v_report;
END;
$function$;

REVOKE ALL ON FUNCTION public.ut_guard_manual_voucher_phase2a(),
  public.ut_guard_manual_owner_gari_projection(),
  public.ut_protect_manual_voucher_expense_item(),
  public.ut_sync_voucher_item_cashbook_trigger()
FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.save_manual_voucher_expense_items(bigint,jsonb),
  public.finalize_manual_voucher(bigint),
  public.get_owner_gari_account_statement_v4(uuid,date,date,date,text,uuid,text),
  public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)
FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.save_manual_voucher_phase2(bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb)
FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.save_manual_voucher_phase2(bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb),
  public.finalize_manual_voucher(bigint),
  public.get_owner_gari_account_statement_v4(uuid,date,date,date,text,uuid,text),
  public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)
TO authenticated;

COMMENT ON TABLE public.manual_vehicle_chakkar_settlements IS
  'Immutable snapshot of a finalized Manual Voucher Chakkar. This additive source never creates Bilty, Movement Group, Loading or Cashbook rows.';
COMMENT ON COLUMN public.owner_gari_account_transactions.source_manual_settlement_id IS
  'Exact-once link for the signed Owner/Gari projection of a finalized Manual Chakkar.';
COMMENT ON FUNCTION public.finalize_manual_voucher(bigint) IS
  'Finalizes Manual Voucher freight less eligible plain regular-trip expense items in one transaction; writes one signed Owner/Gari projection and no Cashbook or Bilty settlement.';
COMMENT ON FUNCTION public.get_vehicle_monthly_hisab_v2(uuid,date,date,date) IS
  'Read-only additive Monthly Hisab combining the existing adjustment-aware Bilty report with immutable Manual Chakkar snapshots.';

COMMIT;
