BEGIN;

DO $adda_account_entry_metadata_precondition$
BEGIN
  IF pg_catalog.to_regclass('public.adda_account_entries') IS NULL
     OR pg_catalog.to_regclass('public.adda_finance_settlements') IS NULL
     OR pg_catalog.to_regclass('public.adda_expenses') IS NULL
     OR pg_catalog.to_regclass('public.adda_other_income') IS NULL
     OR pg_catalog.to_regclass('public.addas') IS NULL
     OR pg_catalog.to_regclass('public.profiles') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_resolve_adda_accounting_tenant(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_other_adda_authorize(uuid,boolean)') IS NULL
     OR pg_catalog.to_regprocedure('public.reverse_adda_finance_entry(uuid,uuid,date,text,uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)') IS NULL
     OR pg_catalog.to_regprocedure('public.get_adda_finance_settlements(uuid,uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.guard_adda_account_entries_append_only()') IS NULL
     OR pg_catalog.to_regprocedure('public.guard_adda_expenses_append_only()') IS NULL
     OR pg_catalog.to_regprocedure('public.guard_adda_other_income_append_only()') IS NULL THEN
    RAISE EXCEPTION 'ADDA_ACCOUNT_METADATA: required Phase 1/2 contract is missing';
  END IF;

  IF pg_catalog.to_regclass('public.adda_account_entry_metadata') IS NOT NULL
     OR pg_catalog.to_regclass('public.adda_account_entry_metadata_history_idx') IS NOT NULL
     OR pg_catalog.to_regclass('public.adda_account_entry_metadata_request_uidx') IS NOT NULL
     OR EXISTS (
       SELECT 1
       FROM pg_catalog.pg_proc AS routine
       JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=routine.pronamespace
       WHERE namespace_row.nspname='public'
         AND routine.proname IN (
           'guard_adda_account_entry_metadata_append_only',
           'update_adda_account_entry_metadata',
           'get_adda_account_entry_metadata'
         )
     ) THEN
    RAISE EXCEPTION 'ADDA_ACCOUNT_METADATA: a metadata object name is already occupied';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE NOT trigger_row.tgisinternal
      AND (
        (trigger_row.tgrelid=pg_catalog.to_regclass('public.adda_account_entry_metadata')
         AND trigger_row.tgname IN (
           'trg_adda_account_entry_metadata_append_only',
           'trg_adda_account_entry_metadata_no_truncate'
         ))
      )
  ) THEN
    RAISE EXCEPTION 'ADDA_ACCOUNT_METADATA: a metadata trigger name is already occupied';
  END IF;
END;
$adda_account_entry_metadata_precondition$;

-- Descriptive edits are immutable revisions. Financial journal/source rows and
-- the Phase 1/2 append-only guards remain untouched.
CREATE TABLE public.adda_account_entry_metadata (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  adda_id uuid NOT NULL,
  account_entry_id uuid NOT NULL,
  revision_no bigint NOT NULL CHECK (revision_no>0),
  reference_no text NULL,
  description text NULL,
  remarks text NULL,
  request_id uuid NOT NULL,
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT adda_account_entry_metadata_entry_adda_fkey
    FOREIGN KEY (adda_id,account_entry_id)
    REFERENCES public.adda_account_entries(adda_id,id) ON DELETE RESTRICT,
  CONSTRAINT adda_account_entry_metadata_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE RESTRICT,
  CONSTRAINT adda_account_entry_metadata_tenant_identity UNIQUE (adda_id,id),
  CONSTRAINT adda_account_entry_metadata_revision_unique UNIQUE (adda_id,account_entry_id,revision_no)
);

CREATE UNIQUE INDEX adda_account_entry_metadata_request_uidx
  ON public.adda_account_entry_metadata(adda_id,request_id);
CREATE INDEX adda_account_entry_metadata_history_idx
  ON public.adda_account_entry_metadata(adda_id,account_entry_id,revision_no DESC,id DESC);

ALTER TABLE public.adda_account_entry_metadata ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION public.guard_adda_account_entry_metadata_append_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
BEGIN
  IF TG_OP='TRUNCATE' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_ACCOUNT_METADATA_APPEND_ONLY';
  END IF;
  IF TG_OP<>'INSERT' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_ACCOUNT_METADATA_APPEND_ONLY';
  END IF;
  IF pg_catalog.current_setting('ut.adda_account_metadata_rpc',true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_ACCOUNT_METADATA_REQUIRES_PROTECTED_RPC';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_adda_account_entry_metadata_append_only
BEFORE INSERT OR UPDATE OR DELETE ON public.adda_account_entry_metadata
FOR EACH ROW EXECUTE FUNCTION public.guard_adda_account_entry_metadata_append_only();
CREATE TRIGGER trg_adda_account_entry_metadata_no_truncate
BEFORE TRUNCATE ON public.adda_account_entry_metadata
FOR EACH STATEMENT EXECUTE FUNCTION public.guard_adda_account_entry_metadata_append_only();

CREATE FUNCTION public.update_adda_account_entry_metadata(
  p_adda_id uuid,
  p_account_entry_id uuid,
  p_reference_no text,
  p_description text,
  p_remarks text,
  p_request_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_adda_id uuid;
  v_authorized_adda uuid;
  v_entry public.adda_account_entries%ROWTYPE;
  v_expense public.adda_expenses%ROWTYPE;
  v_income public.adda_other_income%ROWTYPE;
  v_existing public.adda_account_entry_metadata%ROWTYPE;
  v_reference_no text;
  v_description text;
  v_remarks text;
  v_revision_id uuid;
  v_revision_no bigint;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='AUTHENTICATION_REQUIRED';
  END IF;
  IF p_adda_id IS NULL OR p_account_entry_id IS NULL OR p_request_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_ADDA_ACCOUNT_METADATA_PAYLOAD';
  END IF;
  IF coalesce(pg_catalog.char_length(p_reference_no),0)>120
     OR coalesce(pg_catalog.char_length(p_description),0)>500
     OR coalesce(pg_catalog.char_length(p_remarks),0)>1000 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_ADDA_ACCOUNT_METADATA_PAYLOAD';
  END IF;

  v_adda_id:=public.ut_resolve_adda_accounting_tenant(p_adda_id);
  IF v_adda_id IS DISTINCT FROM p_adda_id THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_AUTHORIZATION_MISMATCH';
  END IF;
  v_authorized_adda:=public.ut_other_adda_authorize(v_adda_id,true);
  IF v_authorized_adda IS DISTINCT FROM v_adda_id THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_AUTHORIZATION_MISMATCH';
  END IF;
  v_reference_no:=nullif(pg_catalog.btrim(p_reference_no),'');
  v_description:=nullif(pg_catalog.btrim(p_description),'');
  v_remarks:=nullif(pg_catalog.btrim(p_remarks),'');

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_adda_id::text||':adda-finance-entry:'||p_account_entry_id::text,0)
  );
  SELECT entry.* INTO v_entry
  FROM public.adda_account_entries AS entry
  WHERE entry.adda_id=v_adda_id AND entry.id=p_account_entry_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='ADDA_FINANCE_ENTRY_NOT_FOUND';
  END IF;

  SELECT metadata.* INTO v_existing
  FROM public.adda_account_entry_metadata AS metadata
  WHERE metadata.adda_id=v_adda_id AND metadata.request_id=p_request_id;
  IF FOUND THEN
    IF v_existing.account_entry_id IS DISTINCT FROM v_entry.id
       OR v_existing.reference_no IS DISTINCT FROM v_reference_no
       OR v_existing.description IS DISTINCT FROM v_description
       OR v_existing.remarks IS DISTINCT FROM v_remarks THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='ADDA_FINANCE_METADATA_IDEMPOTENCY_MISMATCH';
    END IF;
    RETURN v_existing.id;
  END IF;

  IF v_entry.source_type NOT IN ('manual_adda_expense','manual_other_income')
     OR v_entry.reverses_entry_id IS NOT NULL
     OR EXISTS (
       SELECT 1 FROM public.adda_account_entries AS reversal
       WHERE reversal.adda_id=v_adda_id AND reversal.reverses_entry_id=v_entry.id
     ) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_FINANCE_ENTRY_METADATA_NOT_EDITABLE';
  END IF;

  IF v_entry.source_type='manual_adda_expense' THEN
    SELECT source.* INTO v_expense
    FROM public.adda_expenses AS source
    WHERE source.adda_id=v_adda_id
      AND source.id::text=v_entry.source_id
      AND source.event_type='expense'
    FOR UPDATE;
    IF NOT FOUND
       OR v_expense.amount IS DISTINCT FROM v_entry.amount
       OR v_expense.category_id IS DISTINCT FROM v_entry.category_id
       OR v_expense.employee_id IS DISTINCT FROM v_entry.employee_id
       OR v_entry.entry_kind IS DISTINCT FROM 'expense'
       OR v_expense.reference_no IS DISTINCT FROM v_entry.reference_no
       OR v_expense.description IS DISTINCT FROM v_entry.description THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ADDA_FINANCE_SOURCE_EVIDENCE_INCONSISTENT';
    END IF;
  ELSE
    SELECT source.* INTO v_income
    FROM public.adda_other_income AS source
    WHERE source.adda_id=v_adda_id
      AND source.id::text=v_entry.source_id
      AND source.event_type='income'
    FOR UPDATE;
    IF NOT FOUND
       OR v_income.amount IS DISTINCT FROM v_entry.amount
       OR v_entry.entry_kind IS DISTINCT FROM 'income'
       OR v_income.reference_no IS DISTINCT FROM v_entry.reference_no
       OR v_income.description IS DISTINCT FROM v_entry.description THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ADDA_FINANCE_SOURCE_EVIDENCE_INCONSISTENT';
    END IF;
  END IF;

  SELECT coalesce(max(metadata.revision_no),0)+1 INTO v_revision_no
  FROM public.adda_account_entry_metadata AS metadata
  WHERE metadata.adda_id=v_adda_id AND metadata.account_entry_id=v_entry.id;

  PERFORM pg_catalog.set_config('ut.adda_account_metadata_rpc','on',true);
  INSERT INTO public.adda_account_entry_metadata(
    adda_id,account_entry_id,revision_no,reference_no,description,remarks,request_id,created_by
  ) VALUES (
    v_adda_id,v_entry.id,v_revision_no,v_reference_no,v_description,v_remarks,p_request_id,auth.uid()
  ) RETURNING id INTO v_revision_id;
  RETURN v_revision_id;
END;
$function$;

CREATE FUNCTION public.get_adda_account_entry_metadata(
  p_adda_id uuid,
  p_account_entry_ids uuid[]
)
RETURNS TABLE(
  account_entry_id uuid,
  adda_name text,
  reference_no text,
  description text,
  remarks text,
  metadata_updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_adda_id uuid;
BEGIN
  v_adda_id:=public.ut_resolve_adda_accounting_tenant(p_adda_id);
  IF v_adda_id IS DISTINCT FROM p_adda_id THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_AUTHORIZATION_MISMATCH';
  END IF;
  IF p_account_entry_ids IS NULL OR pg_catalog.cardinality(p_account_entry_ids)>200 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_ADDA_ACCOUNT_METADATA_READ_PAYLOAD';
  END IF;

  RETURN QUERY
  SELECT entry.id,
         adda.name,
         CASE WHEN latest.id IS NOT NULL THEN latest.reference_no
              ELSE coalesce(expense_source.reference_no,income_source.reference_no,entry.reference_no)
         END,
         CASE WHEN latest.id IS NOT NULL THEN latest.description
              WHEN entry.reverses_entry_id IS NOT NULL THEN entry.description
              ELSE coalesce(expense_source.description,income_source.description,entry.description)
         END,
         CASE WHEN latest.id IS NOT NULL THEN latest.remarks
              ELSE coalesce(expense_source.remarks,income_source.remarks)
         END,
         latest.created_at
  FROM public.adda_account_entries AS entry
  JOIN public.addas AS adda ON adda.id=entry.adda_id
  LEFT JOIN LATERAL (
    SELECT metadata.id,metadata.reference_no,metadata.description,metadata.remarks,metadata.created_at
    FROM public.adda_account_entry_metadata AS metadata
    WHERE metadata.adda_id=entry.adda_id
      AND metadata.account_entry_id=coalesce(entry.reverses_entry_id,entry.id)
    ORDER BY metadata.revision_no DESC,metadata.id DESC
    LIMIT 1
  ) AS latest ON true
  LEFT JOIN public.adda_expenses AS expense_source
    ON entry.source_type='manual_adda_expense'
   AND expense_source.adda_id=entry.adda_id
   AND expense_source.id::text=entry.source_id
   AND expense_source.event_type='expense'
  LEFT JOIN public.adda_other_income AS income_source
    ON entry.source_type='manual_other_income'
   AND income_source.adda_id=entry.adda_id
   AND income_source.id::text=entry.source_id
   AND income_source.event_type='income'
  WHERE entry.adda_id=v_adda_id
    AND entry.id=ANY(p_account_entry_ids)
  ORDER BY pg_catalog.array_position(p_account_entry_ids,entry.id);
END;
$function$;

REVOKE ALL ON TABLE public.adda_account_entry_metadata
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.guard_adda_account_entry_metadata_append_only()
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.guard_adda_account_entry_metadata_append_only()
  TO service_role;
REVOKE ALL ON FUNCTION public.update_adda_account_entry_metadata(uuid,uuid,text,text,text,uuid),
  public.get_adda_account_entry_metadata(uuid,uuid[])
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.update_adda_account_entry_metadata(uuid,uuid,text,text,text,uuid),
  public.get_adda_account_entry_metadata(uuid,uuid[])
  TO authenticated,service_role;

COMMENT ON TABLE public.adda_account_entry_metadata IS
  'Append-only descriptive metadata revisions for Adda Account entries. Financial source and journal values remain immutable.';

COMMIT;
