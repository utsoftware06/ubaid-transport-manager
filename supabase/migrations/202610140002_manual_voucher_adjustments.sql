BEGIN;

DO $manual_adjustment_preflight$
BEGIN
  IF pg_catalog.to_regclass('public.expenses') IS NULL
     OR pg_catalog.to_regclass('public.manual_voucher_details') IS NULL
     OR pg_catalog.to_regclass('public.manual_vehicle_chakkar_settlements') IS NULL
     OR pg_catalog.to_regclass('public.owner_gari_accounts') IS NULL
     OR pg_catalog.to_regclass('public.owner_gari_account_transactions') IS NULL
     OR pg_catalog.to_regclass('public.vehicles') IS NULL
     OR pg_catalog.to_regclass('public.profiles') IS NULL THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_ADJUSTMENT_REQUIRED_SCHEMA_MISSING';
  END IF;

  IF pg_catalog.to_regprocedure('public.current_user_role()') IS NULL
     OR pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NULL
     OR pg_catalog.to_regprocedure('public.is_super_admin()') IS NULL
     OR pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v4(uuid,date,date,date,text,uuid,text)') IS NULL
     OR pg_catalog.to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_guard_manual_owner_gari_projection()') IS NULL THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_ADJUSTMENT_REQUIRED_ROUTINE_MISSING';
  END IF;

  IF pg_catalog.to_regclass('public.manual_voucher_adjustments') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.save_manual_voucher_adjustment(uuid,bigint,text,date,numeric,numeric,text)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.finalize_manual_voucher_adjustment(uuid)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.reverse_manual_voucher_adjustment(uuid,date,text)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v5(uuid,date,date,date,text,uuid,text)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.get_vehicle_monthly_hisab_v3(uuid,date,date,date)') IS NOT NULL THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_ADJUSTMENT_TARGET_ALREADY_EXISTS';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint constraint_row
    WHERE constraint_row.conrelid=pg_catalog.to_regclass('public.manual_vehicle_chakkar_settlements')
      AND constraint_row.conname='manual_vehicle_chakkar_settlements_id_adda_vehicle_key'
      AND constraint_row.contype='u'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint constraint_row
    WHERE constraint_row.conrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
      AND constraint_row.conname='owner_gari_transactions_type_check'
      AND constraint_row.contype='c'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint constraint_row
    WHERE constraint_row.conrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
      AND constraint_row.conname='owner_gari_transactions_commission_source_check'
      AND constraint_row.contype='c'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint constraint_row
    WHERE constraint_row.conrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
      AND constraint_row.conname='owner_gari_transactions_manual_amount_check'
      AND constraint_row.contype='c'
  ) THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_ADJUSTMENT_OWNER_GARI_CONTRACT_CHANGED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute attribute
    WHERE attribute.attrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
      AND attribute.attname='source_manual_adjustment_id'
      AND attribute.attnum>0 AND NOT attribute.attisdropped
  ) OR EXISTS (
    SELECT 1 FROM public.owner_gari_account_transactions transaction_row
    WHERE transaction_row.transaction_type='manual_chakkar_adjustment'
  ) THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_ADJUSTMENT_OWNER_GARI_TARGET_CONFLICT';
  END IF;
END
$manual_adjustment_preflight$;

CREATE TABLE public.manual_voucher_adjustments (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  manual_settlement_id uuid NOT NULL,
  voucher_id bigint NOT NULL,
  manual_voucher_id uuid NOT NULL,
  adda_id uuid NOT NULL,
  vehicle_id uuid NOT NULL,
  adjustment_no text NOT NULL,
  adjustment_date date NOT NULL,
  freight_adjustment numeric(14,2) NOT NULL DEFAULT 0,
  expense_adjustment numeric(14,2) NOT NULL DEFAULT 0,
  net_adjustment numeric(14,2) NOT NULL,
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'draft',
  reverses_adjustment_id uuid,
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  finalized_by uuid,
  finalized_at timestamptz,

  CONSTRAINT manual_voucher_adjustments_settlement_context_fkey
    FOREIGN KEY(manual_settlement_id,adda_id,vehicle_id)
    REFERENCES public.manual_vehicle_chakkar_settlements(id,adda_id,vehicle_id)
    ON DELETE RESTRICT,
  CONSTRAINT manual_voucher_adjustments_manual_context_fkey
    FOREIGN KEY(manual_voucher_id,adda_id)
    REFERENCES public.manual_voucher_details(id,adda_id)
    ON DELETE RESTRICT,
  CONSTRAINT manual_voucher_adjustments_voucher_fkey
    FOREIGN KEY(voucher_id) REFERENCES public.expenses(id) ON DELETE RESTRICT,
  CONSTRAINT manual_voucher_adjustments_vehicle_adda_fkey
    FOREIGN KEY(vehicle_id,adda_id) REFERENCES public.vehicles(id,adda_id) ON DELETE RESTRICT,
  CONSTRAINT manual_voucher_adjustments_adda_fkey
    FOREIGN KEY(adda_id) REFERENCES public.addas(id) ON DELETE RESTRICT,
  CONSTRAINT manual_voucher_adjustments_created_by_fkey
    FOREIGN KEY(created_by) REFERENCES public.profiles(id) ON DELETE RESTRICT,
  CONSTRAINT manual_voucher_adjustments_finalized_by_fkey
    FOREIGN KEY(finalized_by) REFERENCES public.profiles(id) ON DELETE RESTRICT,
  CONSTRAINT manual_voucher_adjustments_reversal_context_fkey
    FOREIGN KEY(reverses_adjustment_id,adda_id,vehicle_id)
    REFERENCES public.manual_voucher_adjustments(id,adda_id,vehicle_id)
    ON DELETE RESTRICT,
  CONSTRAINT manual_voucher_adjustments_id_adda_vehicle_key
    UNIQUE(id,adda_id,vehicle_id),
  CONSTRAINT manual_voucher_adjustments_number_key
    UNIQUE(adda_id,adjustment_no),
  CONSTRAINT manual_voucher_adjustments_status_check
    CHECK(status IN('draft','finalized')),
  CONSTRAINT manual_voucher_adjustments_number_check
    CHECK(pg_catalog.btrim(adjustment_no)<>''),
  CONSTRAINT manual_voucher_adjustments_reason_check
    CHECK(pg_catalog.btrim(reason)<>''),
  CONSTRAINT manual_voucher_adjustments_amounts_check CHECK(
    freight_adjustment::text NOT IN('NaN','Infinity','-Infinity')
    AND expense_adjustment::text NOT IN('NaN','Infinity','-Infinity')
    AND net_adjustment::text NOT IN('NaN','Infinity','-Infinity')
    AND freight_adjustment=pg_catalog.round(freight_adjustment,2)
    AND expense_adjustment=pg_catalog.round(expense_adjustment,2)
    AND net_adjustment=freight_adjustment-expense_adjustment
    AND net_adjustment<>0
  ),
  CONSTRAINT manual_voucher_adjustments_lifecycle_check CHECK(
    (status='draft' AND finalized_by IS NULL AND finalized_at IS NULL)
    OR (status='finalized' AND finalized_by IS NOT NULL AND finalized_at IS NOT NULL)
  )
);

CREATE INDEX manual_voucher_adjustments_settlement_idx
  ON public.manual_voucher_adjustments(manual_settlement_id,status,created_at,id);
CREATE INDEX manual_voucher_adjustments_voucher_idx
  ON public.manual_voucher_adjustments(voucher_id,status,created_at,id);
CREATE UNIQUE INDEX manual_voucher_adjustments_one_reversal_uidx
  ON public.manual_voucher_adjustments(reverses_adjustment_id)
  WHERE reverses_adjustment_id IS NOT NULL;

ALTER TABLE public.owner_gari_account_transactions
  ADD COLUMN source_manual_adjustment_id uuid,
  DROP CONSTRAINT owner_gari_transactions_type_check,
  DROP CONSTRAINT owner_gari_transactions_commission_source_check,
  ADD CONSTRAINT owner_gari_transactions_manual_adjustment_fkey
    FOREIGN KEY(source_manual_adjustment_id,adda_id,vehicle_id)
    REFERENCES public.manual_voucher_adjustments(id,adda_id,vehicle_id)
    ON DELETE RESTRICT,
  ADD CONSTRAINT owner_gari_transactions_type_check CHECK(transaction_type IN(
    'opening_seed','chakkar_net_credit','owner_withdrawal','gari_withdrawal',
    'monthly_adda_commission','monthly_adda_commission_reversal',
    'monthly_adda_commission_reissue','monthly_adda_commission_adjustment_increase',
    'monthly_adda_commission_adjustment_decrease',
    'monthly_adda_commission_correction_reversal_credit',
    'monthly_adda_commission_correction_reversal_debit',
    'adjustment_credit','adjustment_debit','voucher_adjustment_expense',
    'manual_chakkar_net','manual_chakkar_adjustment'
  )),
  ADD CONSTRAINT owner_gari_transactions_commission_source_check CHECK(
    (transaction_type='chakkar_net_credit'
      AND source_settlement_id IS NOT NULL AND source_adjustment_id IS NULL
      AND source_commission_event_id IS NULL AND source_manual_settlement_id IS NULL
      AND source_manual_adjustment_id IS NULL)
    OR (transaction_type='voucher_adjustment_expense'
      AND source_settlement_id IS NULL AND source_adjustment_id IS NOT NULL
      AND source_commission_event_id IS NULL AND source_manual_settlement_id IS NULL
      AND source_manual_adjustment_id IS NULL)
    OR (transaction_type='manual_chakkar_net'
      AND source_settlement_id IS NULL AND source_adjustment_id IS NULL
      AND source_commission_event_id IS NULL AND source_manual_settlement_id IS NOT NULL
      AND source_manual_adjustment_id IS NULL)
    OR (transaction_type='manual_chakkar_adjustment'
      AND source_settlement_id IS NULL AND source_adjustment_id IS NULL
      AND source_commission_event_id IS NULL AND source_manual_settlement_id IS NULL
      AND source_manual_adjustment_id IS NOT NULL)
    OR (transaction_type IN(
      'monthly_adda_commission','monthly_adda_commission_reversal',
      'monthly_adda_commission_reissue','monthly_adda_commission_adjustment_increase',
      'monthly_adda_commission_adjustment_decrease',
      'monthly_adda_commission_correction_reversal_credit',
      'monthly_adda_commission_correction_reversal_debit'
    ) AND source_settlement_id IS NULL AND source_adjustment_id IS NULL
      AND source_commission_event_id IS NOT NULL AND source_manual_settlement_id IS NULL
      AND source_manual_adjustment_id IS NULL)
    OR (transaction_type NOT IN(
      'chakkar_net_credit','voucher_adjustment_expense','manual_chakkar_net',
      'manual_chakkar_adjustment','monthly_adda_commission',
      'monthly_adda_commission_reversal','monthly_adda_commission_reissue',
      'monthly_adda_commission_adjustment_increase',
      'monthly_adda_commission_adjustment_decrease',
      'monthly_adda_commission_correction_reversal_credit',
      'monthly_adda_commission_correction_reversal_debit'
    ) AND source_settlement_id IS NULL AND source_adjustment_id IS NULL
      AND source_commission_event_id IS NULL AND source_manual_settlement_id IS NULL
      AND source_manual_adjustment_id IS NULL)
  ),
  ADD CONSTRAINT owner_gari_transactions_manual_adjustment_amount_check CHECK(
    transaction_type<>'manual_chakkar_adjustment'
    OR (amount<>0 AND amount::text NOT IN('NaN','Infinity','-Infinity'))
  );

CREATE UNIQUE INDEX owner_gari_transactions_manual_adjustment_uidx
  ON public.owner_gari_account_transactions(source_manual_adjustment_id)
  WHERE source_manual_adjustment_id IS NOT NULL;

ALTER TABLE public.manual_voucher_adjustments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.manual_voucher_adjustments FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.manual_voucher_adjustments TO authenticated;
CREATE POLICY manual_voucher_adjustments_tenant_select
  ON public.manual_voucher_adjustments FOR SELECT TO authenticated
  USING((SELECT public.is_super_admin()) OR adda_id=(SELECT public.current_user_adda_id()));

CREATE FUNCTION public.ut_guard_manual_voucher_adjustment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  original_row public.manual_voucher_adjustments%ROWTYPE;
BEGIN
  IF coalesce(pg_catalog.current_setting('ut.manual_voucher_adjustment_sync',true),'')<>'on' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_RPC_REQUIRED';
  END IF;

  IF TG_OP='DELETE' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_APPEND_ONLY';
  END IF;

  IF TG_OP='UPDATE' THEN
    IF OLD.status<>'draft' THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='FINALIZED_MANUAL_ADJUSTMENT_IS_IMMUTABLE';
    END IF;
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.manual_settlement_id IS DISTINCT FROM OLD.manual_settlement_id
       OR NEW.voucher_id IS DISTINCT FROM OLD.voucher_id
       OR NEW.manual_voucher_id IS DISTINCT FROM OLD.manual_voucher_id
       OR NEW.adda_id IS DISTINCT FROM OLD.adda_id
       OR NEW.vehicle_id IS DISTINCT FROM OLD.vehicle_id
       OR NEW.created_by IS DISTINCT FROM OLD.created_by
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.reverses_adjustment_id IS DISTINCT FROM OLD.reverses_adjustment_id THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_CONTEXT_IMMUTABLE';
    END IF;
    IF NEW.status='finalized' AND (
      coalesce(pg_catalog.current_setting('ut.manual_voucher_adjustment_finalizing',true),'')<>'on'
      OR NEW.adjustment_no IS DISTINCT FROM OLD.adjustment_no
      OR NEW.adjustment_date IS DISTINCT FROM OLD.adjustment_date
      OR NEW.freight_adjustment IS DISTINCT FROM OLD.freight_adjustment
      OR NEW.expense_adjustment IS DISTINCT FROM OLD.expense_adjustment
      OR NEW.net_adjustment IS DISTINCT FROM OLD.net_adjustment
      OR NEW.reason IS DISTINCT FROM OLD.reason
      OR NEW.finalized_by IS NULL OR NEW.finalized_at IS NULL
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_FINALIZATION_TRANSITION_INVALID';
    END IF;
    IF NEW.status NOT IN('draft','finalized') THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_STATUS_INVALID';
    END IF;
  ELSIF TG_OP='INSERT' THEN
    IF NEW.status<>'draft' OR NEW.finalized_by IS NOT NULL OR NEW.finalized_at IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_MUST_START_DRAFT';
    END IF;
  END IF;

  IF NOT EXISTS(
    SELECT 1
    FROM public.manual_voucher_details detail
    JOIN public.expenses voucher ON voucher.id=detail.voucher_id
    JOIN public.manual_vehicle_chakkar_settlements settlement
      ON settlement.manual_voucher_id=detail.id
     AND settlement.voucher_id=detail.voucher_id
     AND settlement.adda_id=detail.adda_id
     AND settlement.vehicle_id=detail.vehicle_id
    WHERE detail.id=NEW.manual_voucher_id
      AND detail.voucher_id=NEW.voucher_id
      AND detail.adda_id=NEW.adda_id
      AND detail.vehicle_id=NEW.vehicle_id
      AND detail.status='finalized'
      AND settlement.id=NEW.manual_settlement_id
      AND voucher.voucher_source='manual'
      AND voucher.archived_at IS NULL
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_SOURCE_CONTEXT_INVALID';
  END IF;

  IF NEW.reverses_adjustment_id IS NOT NULL THEN
    SELECT adjustment.* INTO original_row
    FROM public.manual_voucher_adjustments adjustment
    WHERE adjustment.id=NEW.reverses_adjustment_id
      AND adjustment.status='finalized'
      AND adjustment.manual_settlement_id=NEW.manual_settlement_id
      AND adjustment.voucher_id=NEW.voucher_id
      AND adjustment.manual_voucher_id=NEW.manual_voucher_id
      AND adjustment.adda_id=NEW.adda_id
      AND adjustment.vehicle_id=NEW.vehicle_id
    FOR KEY SHARE;
    IF NOT FOUND
       OR NEW.freight_adjustment IS DISTINCT FROM -original_row.freight_adjustment
       OR NEW.expense_adjustment IS DISTINCT FROM -original_row.expense_adjustment
       OR NEW.net_adjustment IS DISTINCT FROM -original_row.net_adjustment THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_REVERSAL_INVALID';
    END IF;
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER manual_voucher_adjustments_protect
BEFORE INSERT OR UPDATE OR DELETE ON public.manual_voucher_adjustments
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_manual_voucher_adjustment();

CREATE OR REPLACE FUNCTION public.ut_guard_manual_owner_gari_projection()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_settlement public.manual_vehicle_chakkar_settlements%ROWTYPE;
  v_adjustment public.manual_voucher_adjustments%ROWTYPE;
  v_detail_status text;
BEGIN
  IF TG_OP='UPDATE' AND (
       OLD.transaction_type IN('manual_chakkar_net','manual_chakkar_adjustment')
       OR NEW.transaction_type IN('manual_chakkar_net','manual_chakkar_adjustment'))
     OR TG_OP='DELETE' AND OLD.transaction_type IN('manual_chakkar_net','manual_chakkar_adjustment') THEN
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
       OR NEW.source_commission_event_id IS NOT NULL
       OR NEW.source_manual_adjustment_id IS NOT NULL THEN
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
  ELSIF TG_OP='INSERT' AND NEW.transaction_type='manual_chakkar_adjustment' THEN
    IF coalesce(pg_catalog.current_setting('ut.manual_voucher_adjustment_finalizing',true),'')<>'on' THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_OWNER_GARI_ADJUSTMENT_RPC_REQUIRED';
    END IF;
    SELECT adjustment.* INTO v_adjustment
    FROM public.manual_voucher_adjustments adjustment
    WHERE adjustment.id=NEW.source_manual_adjustment_id
      AND adjustment.adda_id=NEW.adda_id AND adjustment.vehicle_id=NEW.vehicle_id
      AND adjustment.status='draft'
    FOR KEY SHARE;
    IF NOT FOUND
       OR NEW.amount IS DISTINCT FROM v_adjustment.net_adjustment
       OR NEW.transaction_date IS DISTINCT FROM v_adjustment.adjustment_date
       OR NEW.source_settlement_id IS NOT NULL OR NEW.source_adjustment_id IS NOT NULL
       OR NEW.source_commission_event_id IS NOT NULL
       OR NEW.source_manual_settlement_id IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_OWNER_GARI_ADJUSTMENT_PROJECTION_MISMATCH';
    END IF;
  END IF;

  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END
$function$;

CREATE FUNCTION public.save_manual_voucher_adjustment(
  p_adjustment_id uuid,
  p_voucher_id bigint,
  p_adjustment_no text,
  p_adjustment_date date,
  p_freight_adjustment numeric,
  p_expense_adjustment numeric,
  p_reason text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  actor_id uuid:=auth.uid();
  actor_role text;
  adjustment_row public.manual_voucher_adjustments%ROWTYPE;
  detail_row public.manual_voucher_details%ROWTYPE;
  settlement_row public.manual_vehicle_chakkar_settlements%ROWTYPE;
  saved_id uuid;
  normalized_no text:=NULLIF(pg_catalog.btrim(p_adjustment_no),'');
  normalized_reason text:=NULLIF(pg_catalog.btrim(p_reason),'');
  net_value numeric(14,2);
BEGIN
  IF actor_id IS NULL OR NOT EXISTS(
    SELECT 1 FROM public.profiles profile WHERE profile.id=actor_id AND profile.is_active=true
  ) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='AUTHENTICATION_REQUIRED'; END IF;
  actor_role:=public.current_user_role();
  IF actor_role IS NULL OR actor_role NOT IN('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_ROLE_REQUIRED';
  END IF;
  IF p_voucher_id IS NULL OR p_adjustment_date IS NULL OR normalized_no IS NULL
     OR normalized_reason IS NULL OR p_freight_adjustment IS NULL OR p_expense_adjustment IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_REQUIRED_FIELDS';
  END IF;
  IF p_freight_adjustment::text IN('NaN','Infinity','-Infinity')
     OR p_expense_adjustment::text IN('NaN','Infinity','-Infinity')
     OR p_freight_adjustment<>pg_catalog.round(p_freight_adjustment,2)
     OR p_expense_adjustment<>pg_catalog.round(p_expense_adjustment,2)
     OR pg_catalog.abs(p_freight_adjustment)>999999999999.99
     OR pg_catalog.abs(p_expense_adjustment)>999999999999.99 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_AMOUNT_INVALID';
  END IF;
  net_value:=(p_freight_adjustment-p_expense_adjustment)::numeric(14,2);
  IF net_value=0 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_NET_MUST_BE_NONZERO';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('manual-voucher-adjustment-voucher:'||p_voucher_id::text,0)
  );
  SELECT detail.* INTO detail_row
  FROM public.manual_voucher_details detail
  JOIN public.expenses voucher ON voucher.id=detail.voucher_id
  WHERE detail.voucher_id=p_voucher_id
    AND voucher.voucher_source='manual' AND voucher.archived_at IS NULL
    AND detail.status='finalized'
  FOR UPDATE OF detail,voucher;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='FINALIZED_MANUAL_VOUCHER_REQUIRED'; END IF;
  IF NOT public.is_super_admin() AND detail_row.adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_BELONGS_TO_ANOTHER_ADDA';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.vehicles vehicle
    WHERE vehicle.id=detail_row.vehicle_id AND vehicle.adda_id=detail_row.adda_id) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_VEHICLE_CONTEXT_INVALID';
  END IF;
  SELECT settlement.* INTO settlement_row
  FROM public.manual_vehicle_chakkar_settlements settlement
  WHERE settlement.voucher_id=p_voucher_id
    AND settlement.manual_voucher_id=detail_row.id
    AND settlement.adda_id=detail_row.adda_id
    AND settlement.vehicle_id=detail_row.vehicle_id
  FOR KEY SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_SETTLEMENT_MISSING'; END IF;

  PERFORM pg_catalog.set_config('ut.manual_voucher_adjustment_sync','on',true);
  IF p_adjustment_id IS NULL THEN
    saved_id:=pg_catalog.gen_random_uuid();
    INSERT INTO public.manual_voucher_adjustments(
      id,manual_settlement_id,voucher_id,manual_voucher_id,adda_id,vehicle_id,
      adjustment_no,adjustment_date,freight_adjustment,expense_adjustment,
      net_adjustment,reason,status,created_by
    ) VALUES(
      saved_id,settlement_row.id,p_voucher_id,detail_row.id,detail_row.adda_id,
      detail_row.vehicle_id,normalized_no,p_adjustment_date,
      p_freight_adjustment,p_expense_adjustment,net_value,normalized_reason,'draft',actor_id
    );
  ELSE
    SELECT adjustment.* INTO adjustment_row
    FROM public.manual_voucher_adjustments adjustment
    WHERE adjustment.id=p_adjustment_id FOR UPDATE;
    IF NOT FOUND OR adjustment_row.status<>'draft'
       OR adjustment_row.voucher_id IS DISTINCT FROM p_voucher_id
       OR adjustment_row.manual_settlement_id IS DISTINCT FROM settlement_row.id
       OR adjustment_row.manual_voucher_id IS DISTINCT FROM detail_row.id
       OR adjustment_row.adda_id IS DISTINCT FROM detail_row.adda_id
       OR adjustment_row.vehicle_id IS DISTINCT FROM detail_row.vehicle_id
       OR adjustment_row.reverses_adjustment_id IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_DRAFT_CONTEXT_INVALID';
    END IF;
    saved_id:=adjustment_row.id;
    UPDATE public.manual_voucher_adjustments adjustment
    SET adjustment_no=normalized_no,adjustment_date=p_adjustment_date,
        freight_adjustment=p_freight_adjustment,expense_adjustment=p_expense_adjustment,
        net_adjustment=net_value,reason=normalized_reason
    WHERE adjustment.id=saved_id AND adjustment.status='draft';
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_SAVE_FAILED'; END IF;
  END IF;
  RETURN saved_id;
END
$function$;

CREATE FUNCTION public.finalize_manual_voucher_adjustment(p_adjustment_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  actor_id uuid:=auth.uid();
  actor_role text;
  adjustment_row public.manual_voucher_adjustments%ROWTYPE;
  detail_row public.manual_voucher_details%ROWTYPE;
  voucher_row public.expenses%ROWTYPE;
  owner_account_id uuid;
  projection_count integer;
BEGIN
  IF actor_id IS NULL OR NOT EXISTS(
    SELECT 1 FROM public.profiles profile WHERE profile.id=actor_id AND profile.is_active=true
  ) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='AUTHENTICATION_REQUIRED'; END IF;
  actor_role:=public.current_user_role();
  IF actor_role IS NULL OR actor_role NOT IN('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_ROLE_REQUIRED';
  END IF;
  IF p_adjustment_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_ID_REQUIRED'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('manual-voucher-adjustment:'||p_adjustment_id::text,0));
  SELECT adjustment.* INTO adjustment_row
  FROM public.manual_voucher_adjustments adjustment
  WHERE adjustment.id=p_adjustment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_NOT_FOUND'; END IF;
  IF NOT public.is_super_admin() AND adjustment_row.adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_BELONGS_TO_ANOTHER_ADDA';
  END IF;

  IF adjustment_row.status='finalized' THEN
    SELECT pg_catalog.count(*)::integer INTO projection_count
    FROM public.owner_gari_account_transactions transaction_row
    WHERE transaction_row.source_manual_adjustment_id=p_adjustment_id
      AND transaction_row.transaction_type='manual_chakkar_adjustment'
      AND transaction_row.adda_id=adjustment_row.adda_id
      AND transaction_row.vehicle_id=adjustment_row.vehicle_id
      AND transaction_row.amount=adjustment_row.net_adjustment
      AND transaction_row.transaction_date=adjustment_row.adjustment_date;
    IF projection_count<>1 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_PROJECTION_CONFLICT'; END IF;
    RETURN p_adjustment_id;
  END IF;
  IF adjustment_row.status<>'draft' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_STATUS_INVALID'; END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('manual-voucher-adjustment-voucher:'||adjustment_row.voucher_id::text,0));
  SELECT voucher.* INTO voucher_row
  FROM public.expenses voucher
  WHERE voucher.id=adjustment_row.voucher_id
    AND voucher.voucher_source='manual' AND voucher.archived_at IS NULL
  FOR UPDATE;
  SELECT detail.* INTO detail_row
  FROM public.manual_voucher_details detail
  WHERE detail.id=adjustment_row.manual_voucher_id
    AND detail.voucher_id=adjustment_row.voucher_id
    AND detail.adda_id=adjustment_row.adda_id
    AND detail.vehicle_id=adjustment_row.vehicle_id
    AND detail.status='finalized'
  FOR KEY SHARE;
  IF NOT FOUND OR voucher_row.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='FINALIZED_MANUAL_VOUCHER_CONTEXT_REQUIRED'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.manual_vehicle_chakkar_settlements settlement
    WHERE settlement.id=adjustment_row.manual_settlement_id
      AND settlement.voucher_id=adjustment_row.voucher_id
      AND settlement.manual_voucher_id=adjustment_row.manual_voucher_id
      AND settlement.adda_id=adjustment_row.adda_id
      AND settlement.vehicle_id=adjustment_row.vehicle_id) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_SETTLEMENT_CONTEXT_INVALID';
  END IF;
  IF adjustment_row.net_adjustment IS DISTINCT FROM adjustment_row.freight_adjustment-adjustment_row.expense_adjustment
     OR adjustment_row.net_adjustment=0 THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_TOTAL_INVALID';
  END IF;
  IF EXISTS(SELECT 1 FROM public.owner_gari_account_transactions transaction_row
    WHERE transaction_row.source_manual_adjustment_id=p_adjustment_id) THEN
    RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_ALREADY_POSTED';
  END IF;
  SELECT account.id INTO owner_account_id
  FROM public.owner_gari_accounts account
  WHERE account.adda_id=adjustment_row.adda_id
    AND account.vehicle_id=adjustment_row.vehicle_id
  FOR UPDATE;
  IF owner_account_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='OWNER_GARI_ACCOUNT_NOT_FOUND'; END IF;

  PERFORM pg_catalog.set_config('ut.owner_gari_foundation_sync','on',true);
  PERFORM pg_catalog.set_config('ut.manual_voucher_adjustment_finalizing','on',true);
  INSERT INTO public.owner_gari_account_transactions(
    account_id,adda_id,vehicle_id,transaction_date,transaction_type,amount,
    source_manual_adjustment_id,reference_no,description,created_by
  ) VALUES(
    owner_account_id,adjustment_row.adda_id,adjustment_row.vehicle_id,
    adjustment_row.adjustment_date,'manual_chakkar_adjustment',adjustment_row.net_adjustment,
    adjustment_row.id,adjustment_row.adjustment_no,
    'Manual Voucher Adjustment '||adjustment_row.adjustment_no||' against Voucher '||adjustment_row.voucher_id::text,
    actor_id
  );
  PERFORM pg_catalog.set_config('ut.manual_voucher_adjustment_sync','on',true);
  UPDATE public.manual_voucher_adjustments adjustment
  SET status='finalized',finalized_by=actor_id,finalized_at=pg_catalog.clock_timestamp()
  WHERE adjustment.id=p_adjustment_id AND adjustment.status='draft';
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_FINALIZATION_FAILED'; END IF;
  RETURN p_adjustment_id;
END
$function$;

CREATE FUNCTION public.reverse_manual_voucher_adjustment(
  p_adjustment_id uuid,
  p_reversal_date date,
  p_reason text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  actor_id uuid:=auth.uid();
  actor_role text;
  original_row public.manual_voucher_adjustments%ROWTYPE;
  reversal_row public.manual_voucher_adjustments%ROWTYPE;
  reversal_id uuid;
  reversal_no text;
  projection_count integer;
BEGIN
  IF actor_id IS NULL OR NOT EXISTS(
    SELECT 1 FROM public.profiles profile WHERE profile.id=actor_id AND profile.is_active=true
  ) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='AUTHENTICATION_REQUIRED'; END IF;
  actor_role:=public.current_user_role();
  IF actor_role IS NULL OR actor_role NOT IN('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_ROLE_REQUIRED';
  END IF;
  IF p_adjustment_id IS NULL OR p_reversal_date IS NULL OR NULLIF(pg_catalog.btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_REVERSAL_FIELDS_REQUIRED';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('manual-voucher-adjustment:'||p_adjustment_id::text,0));
  SELECT adjustment.* INTO original_row
  FROM public.manual_voucher_adjustments adjustment
  WHERE adjustment.id=p_adjustment_id FOR UPDATE;
  IF NOT FOUND OR original_row.status<>'finalized' OR original_row.reverses_adjustment_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='FINALIZED_MANUAL_ADJUSTMENT_REQUIRED_FOR_REVERSAL';
  END IF;
  IF NOT public.is_super_admin() AND original_row.adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_BELONGS_TO_ANOTHER_ADDA';
  END IF;
  SELECT adjustment.* INTO reversal_row
  FROM public.manual_voucher_adjustments adjustment
  WHERE adjustment.reverses_adjustment_id=p_adjustment_id;
  IF FOUND THEN
    SELECT pg_catalog.count(*)::integer INTO projection_count
    FROM public.owner_gari_account_transactions transaction_row
    WHERE transaction_row.source_manual_adjustment_id=reversal_row.id
      AND transaction_row.transaction_type='manual_chakkar_adjustment';
    IF reversal_row.status='finalized' AND projection_count=1 THEN RETURN reversal_row.id; END IF;
    RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='MANUAL_VOUCHER_ADJUSTMENT_REVERSAL_ALREADY_EXISTS';
  END IF;

  reversal_id:=pg_catalog.gen_random_uuid();
  reversal_no:='REV-'||original_row.adjustment_no||'-'||pg_catalog.substr(reversal_id::text,1,8);
  PERFORM pg_catalog.set_config('ut.manual_voucher_adjustment_sync','on',true);
  INSERT INTO public.manual_voucher_adjustments(
    id,manual_settlement_id,voucher_id,manual_voucher_id,adda_id,vehicle_id,
    adjustment_no,adjustment_date,freight_adjustment,expense_adjustment,
    net_adjustment,reason,status,reverses_adjustment_id,created_by
  ) VALUES(
    reversal_id,original_row.manual_settlement_id,original_row.voucher_id,
    original_row.manual_voucher_id,original_row.adda_id,original_row.vehicle_id,
    reversal_no,p_reversal_date,-original_row.freight_adjustment,
    -original_row.expense_adjustment,-original_row.net_adjustment,
    pg_catalog.btrim(p_reason),'draft',original_row.id,actor_id
  );
  PERFORM public.finalize_manual_voucher_adjustment(reversal_id);
  RETURN reversal_id;
END
$function$;

CREATE FUNCTION public.get_vehicle_monthly_hisab_v3(
  p_vehicle_id uuid,
  p_month date,
  p_date_from date,
  p_date_to date
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
  v_rows jsonb;
  v_adda_id uuid;
  v_use_range boolean:=p_date_from IS NOT NULL OR p_date_to IS NOT NULL;
  v_month_start date;
  v_freight_adjustment numeric:=0;
  v_expense_adjustment numeric:=0;
  v_net_adjustment numeric:=0;
  v_adjustment_count bigint:=0;
BEGIN
  v_report:=public.get_vehicle_monthly_hisab_v2(p_vehicle_id,p_month,p_date_from,p_date_to);
  v_adda_id:=(v_report->'vehicle'->>'adda_id')::uuid;
  IF NOT v_use_range AND p_month IS NOT NULL THEN
    v_month_start:=pg_catalog.date_trunc('month',p_month)::date;
  END IF;

  SELECT coalesce(pg_catalog.sum(adjustment.freight_adjustment),0),
         coalesce(pg_catalog.sum(adjustment.expense_adjustment),0),
         coalesce(pg_catalog.sum(adjustment.net_adjustment),0),
         pg_catalog.count(*)::bigint
  INTO v_freight_adjustment,v_expense_adjustment,v_net_adjustment,v_adjustment_count
  FROM public.manual_voucher_adjustments adjustment
  JOIN public.manual_vehicle_chakkar_settlements settlement
    ON settlement.id=adjustment.manual_settlement_id
   AND settlement.adda_id=adjustment.adda_id
   AND settlement.vehicle_id=adjustment.vehicle_id
  WHERE adjustment.status='finalized'
    AND settlement.adda_id=v_adda_id AND settlement.vehicle_id=p_vehicle_id
    AND ((v_use_range
      AND (p_date_from IS NULL OR settlement.settlement_date>=p_date_from)
      AND (p_date_to IS NULL OR settlement.settlement_date<=p_date_to))
      OR (NOT v_use_range AND settlement.settlement_date>=v_month_start
      AND settlement.settlement_date<(v_month_start+INTERVAL '1 month')::date));

  SELECT coalesce(pg_catalog.jsonb_agg(
    CASE WHEN row_value.value->>'source_type'='manual' THEN
      row_value.value || pg_catalog.jsonb_build_object(
        'original_chakkar_net',coalesce((row_value.value->>'net_vehicle_amount')::numeric,0),
        'adjustment_freight_total',coalesce(adjustment_totals.freight_total,0),
        'adjustment_expense_total',coalesce(adjustment_totals.expense_total,0),
        'adjustment_total',coalesce(adjustment_totals.net_total,0),
        'adjustment_count',coalesce(adjustment_totals.adjustment_count,0),
        'adjusted_net_vehicle_amount',coalesce((row_value.value->>'net_vehicle_amount')::numeric,0)
          +coalesce(adjustment_totals.net_total,0),
        'adjusted_vehicle_freight',coalesce((row_value.value->>'vehicle_freight')::numeric,0)
          +coalesce(adjustment_totals.freight_total,0),
        'adjusted_total_expenses',coalesce((row_value.value->>'total_expenses')::numeric,0)
          +coalesce(adjustment_totals.expense_total,0)
      )
      ELSE row_value.value END
    ORDER BY row_value.ordinality),'[]'::jsonb)
  INTO v_rows
  FROM pg_catalog.jsonb_array_elements(v_report->'chakkars') WITH ORDINALITY AS row_value(value,ordinality)
  LEFT JOIN LATERAL (
    SELECT coalesce(pg_catalog.sum(adjustment.freight_adjustment),0) freight_total,
           coalesce(pg_catalog.sum(adjustment.expense_adjustment),0) expense_total,
           coalesce(pg_catalog.sum(adjustment.net_adjustment),0) net_total,
           pg_catalog.count(*)::bigint adjustment_count
    FROM public.manual_voucher_adjustments adjustment
    WHERE adjustment.manual_settlement_id=(row_value.value->>'manual_settlement_id')::uuid
      AND adjustment.adda_id=v_adda_id AND adjustment.vehicle_id=p_vehicle_id
      AND adjustment.status='finalized'
  ) adjustment_totals ON row_value.value->>'source_type'='manual';

  v_summary:=coalesce(v_report->'summary','{}'::jsonb)
    || pg_catalog.jsonb_build_object(
      'total_vehicle_freight',coalesce((v_report->'summary'->>'total_vehicle_freight')::numeric,0)+v_freight_adjustment,
      'total_regular_trip_expenses',coalesce((v_report->'summary'->>'total_regular_trip_expenses')::numeric,0)+v_expense_adjustment,
      'total_expenses',coalesce((v_report->'summary'->>'total_expenses')::numeric,0)+v_expense_adjustment,
      'vehicle_monthly_profit',coalesce((v_report->'summary'->>'vehicle_monthly_profit')::numeric,0)+v_net_adjustment,
      'total_manual_chakkar_freight_adjustments',v_freight_adjustment,
      'total_manual_chakkar_expense_adjustments',v_expense_adjustment,
      'total_manual_chakkar_adjustments',v_net_adjustment,
      'manual_chakkar_adjustment_count',v_adjustment_count
    );
  v_breakdown:=coalesce(v_report->'expense_breakdown','{}'::jsonb)
    || pg_catalog.jsonb_build_object(
      'manual_chakkar_freight_adjustments',v_freight_adjustment,
      'manual_chakkar_expense_adjustments',v_expense_adjustment,
      'manual_chakkar_net_adjustments',v_net_adjustment
    );
  v_report:=pg_catalog.jsonb_set(v_report,'{summary}',v_summary,true);
  v_report:=pg_catalog.jsonb_set(v_report,'{expense_breakdown}',v_breakdown,true);
  v_report:=pg_catalog.jsonb_set(v_report,'{chakkars}',v_rows,true);
  RETURN v_report;
END
$function$;

CREATE FUNCTION public.get_owner_gari_account_statement_v5(
  p_vehicle_id uuid,
  p_month date DEFAULT NULL,
  p_date_from date DEFAULT NULL,
  p_date_to date DEFAULT NULL,
  p_transaction_type text DEFAULT NULL,
  p_movement_group_id uuid DEFAULT NULL,
  p_search text DEFAULT NULL
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
  v_start date;
  v_end date;
  v_transactions jsonb;
  v_adjustment_credit numeric:=0;
  v_adjustment_debit numeric:=0;
  v_adjustment_net numeric:=0;
  v_allowed_types text[]:=ARRAY[
    'opening_seed','chakkar_net_credit','manual_chakkar_net','manual_chakkar_adjustment',
    'owner_withdrawal','gari_withdrawal','monthly_adda_commission',
    'monthly_adda_commission_reversal','monthly_adda_commission_reissue',
    'monthly_adda_commission_adjustment_increase','monthly_adda_commission_adjustment_decrease',
    'monthly_adda_commission_correction_reversal_credit',
    'monthly_adda_commission_correction_reversal_debit','adjustment_credit',
    'adjustment_debit','voucher_adjustment_expense'
  ];
BEGIN
  IF p_transaction_type IS NOT NULL AND NOT(p_transaction_type=ANY(v_allowed_types)) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_OWNER_GARI_TRANSACTION_TYPE';
  END IF;

  -- v4 remains untouched. It supplies tenant authorization, account context,
  -- period semantics, movement/search filters, and all historical rows.
  v_report:=public.get_owner_gari_account_statement_v4(
    p_vehicle_id,p_month,p_date_from,p_date_to,NULL,p_movement_group_id,p_search
  );
  v_adda_id:=(v_report->'account'->>'adda_id')::uuid;
  v_start:=NULLIF(v_report->'period'->>'date_from','')::date;
  v_end:=NULLIF(v_report->'period'->>'date_to','')::date;

  SELECT coalesce(pg_catalog.sum(transaction_row.amount) FILTER(WHERE transaction_row.amount>0),0),
         coalesce(pg_catalog.sum(-transaction_row.amount) FILTER(WHERE transaction_row.amount<0),0),
         coalesce(pg_catalog.sum(transaction_row.amount),0)
  INTO v_adjustment_credit,v_adjustment_debit,v_adjustment_net
  FROM public.owner_gari_account_transactions transaction_row
  WHERE transaction_row.adda_id=v_adda_id AND transaction_row.vehicle_id=p_vehicle_id
    AND transaction_row.transaction_type='manual_chakkar_adjustment'
    AND (v_start IS NULL OR transaction_row.transaction_date>=v_start)
    AND (v_end IS NULL OR transaction_row.transaction_date<=v_end);

  SELECT coalesce(pg_catalog.jsonb_agg(
    row_value.value || CASE WHEN transaction_row.transaction_type='manual_chakkar_adjustment'
      THEN pg_catalog.jsonb_build_object(
        'source_manual_adjustment_id',adjustment.id,
        'manual_adjustment_id',adjustment.id,
        'manual_settlement_id',adjustment.manual_settlement_id,
        'manual_voucher_id',adjustment.manual_voucher_id,
        'voucher_id',adjustment.voucher_id,
        'adjustment_no',adjustment.adjustment_no,
        'adjustment_reason',adjustment.reason,
        'adjustment_net',adjustment.net_adjustment,
        'reverses_adjustment_id',adjustment.reverses_adjustment_id,
        'movement_group_id',NULL,
        'return_bilty_id',NULL
      ) ELSE '{}'::jsonb END
    ORDER BY row_value.ordinality),'[]'::jsonb)
  INTO v_transactions
  FROM pg_catalog.jsonb_array_elements(v_report->'transactions') WITH ORDINALITY AS row_value(value,ordinality)
  LEFT JOIN public.owner_gari_account_transactions transaction_row
    ON transaction_row.id=(row_value.value->>'transaction_id')::uuid
   AND transaction_row.adda_id=v_adda_id AND transaction_row.vehicle_id=p_vehicle_id
  LEFT JOIN public.manual_voucher_adjustments adjustment
    ON adjustment.id=transaction_row.source_manual_adjustment_id
   AND adjustment.adda_id=v_adda_id AND adjustment.vehicle_id=p_vehicle_id
   AND adjustment.status='finalized'
  WHERE p_transaction_type IS NULL OR row_value.value->>'transaction_type'=p_transaction_type;

  v_report:=pg_catalog.jsonb_set(v_report,'{transactions}',v_transactions,true);
  v_report:=pg_catalog.jsonb_set(v_report,'{summary}',
    coalesce(v_report->'summary','{}'::jsonb)
      || pg_catalog.jsonb_build_object(
        'total_manual_chakkar_adjustment_credit',v_adjustment_credit,
        'total_manual_chakkar_adjustment_debit',v_adjustment_debit,
        'total_manual_chakkar_adjustment_net',v_adjustment_net
      ),true);
  RETURN v_report;
END
$function$;

REVOKE ALL ON FUNCTION public.ut_guard_manual_voucher_adjustment(),
  public.ut_guard_manual_owner_gari_projection()
FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.save_manual_voucher_adjustment(uuid,bigint,text,date,numeric,numeric,text),
  public.finalize_manual_voucher_adjustment(uuid),
  public.reverse_manual_voucher_adjustment(uuid,date,text),
  public.get_owner_gari_account_statement_v5(uuid,date,date,date,text,uuid,text),
  public.get_vehicle_monthly_hisab_v3(uuid,date,date,date)
FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.save_manual_voucher_adjustment(uuid,bigint,text,date,numeric,numeric,text),
  public.finalize_manual_voucher_adjustment(uuid),
  public.reverse_manual_voucher_adjustment(uuid,date,text),
  public.get_owner_gari_account_statement_v5(uuid,date,date,date,text,uuid,text),
  public.get_vehicle_monthly_hisab_v3(uuid,date,date,date)
TO authenticated;

COMMENT ON TABLE public.manual_voucher_adjustments IS
  'Append-only Manual Chakkar adjustments linked to the immutable Manual settlement, Voucher, and exact Owner/Gari projection. Reversals are separate offsetting records; no Cashbook or freight income rows are created.';
COMMENT ON COLUMN public.owner_gari_account_transactions.source_manual_adjustment_id IS
  'Exact-once source for a signed Manual Chakkar adjustment Owner/Gari projection.';
COMMENT ON FUNCTION public.finalize_manual_voucher_adjustment(uuid) IS
  'Finalizes one draft Manual Chakkar adjustment, preserves the original settlement, and posts exactly one signed Owner/Gari transaction without Cashbook writes.';
COMMENT ON FUNCTION public.reverse_manual_voucher_adjustment(uuid,date,text) IS
  'Creates an immutable inverse Manual Chakkar adjustment and its exact-once Owner/Gari projection; the original adjustment is not edited.';
COMMENT ON FUNCTION public.get_vehicle_monthly_hisab_v3(uuid,date,date,date) IS
  'Monthly Hisab version 3 layers finalized Manual Voucher adjustments over immutable Chakkar settlement snapshots; version 2 remains preserved.';
COMMENT ON FUNCTION public.get_owner_gari_account_statement_v5(uuid,date,date,date,text,uuid,text) IS
  'Additive Owner/Gari statement version 5 exposes Manual Chakkar adjustment projections and their exact Voucher/source metadata while preserving v4.';

COMMIT;
