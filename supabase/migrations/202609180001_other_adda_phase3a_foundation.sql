-- Phase 3A: isolated NON-CASH foundation. No drafts or settlement states.
-- Forward-only, single transaction; deliberately fails on object collision/rerun.
-- Apply once through migration tracking. Operators read/post; admins manage/reverse.
-- Super admins must explicitly resolve a target tenant; no implicit global write.
BEGIN;
CREATE TABLE public.other_addas (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 adda_id uuid NOT NULL REFERENCES public.addas(id) ON DELETE RESTRICT,
 adda_name text NOT NULL CHECK (btrim(adda_name) <> ''),
 contact_person text, mobile text, whatsapp text, city text, address text,
 ntn_cnic text, notes text,
 business_type text NOT NULL DEFAULT 'regular' CHECK (business_type IN ('regular','one_time')),
 status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','archived')),
 created_at timestamptz NOT NULL DEFAULT now(),
 created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
 updated_at timestamptz NOT NULL DEFAULT now(),
 updated_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
 archived_at timestamptz, archived_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
 CONSTRAINT other_addas_tenant_identity UNIQUE (adda_id,id),
 CONSTRAINT other_addas_archive_state CHECK (
 (status='active' AND archived_at IS NULL AND archived_by IS NULL) OR
 (status='archived' AND archived_at IS NOT NULL AND archived_by IS NOT NULL))
);
CREATE TABLE public.other_adda_transactions (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 adda_id uuid NOT NULL,
 other_adda_id uuid NOT NULL,
 transaction_date date NOT NULL,
 side text NOT NULL CHECK (side IN ('receivable','payable')),
 amount numeric(18,2) NOT NULL CHECK (amount>0 AND amount::text NOT IN ('NaN','Infinity','-Infinity')),
 description text NOT NULL CHECK (btrim(description)<>''), reference_no text,
 event_type text NOT NULL CHECK (event_type IN ('obligation','reversal')),
 origin text NOT NULL DEFAULT 'manual' CHECK (origin='manual'),
 request_id uuid NOT NULL,
 reverses_transaction_id uuid,
 created_at timestamptz NOT NULL DEFAULT now(),
 created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
 CONSTRAINT other_adda_transactions_master_fk FOREIGN KEY (adda_id,other_adda_id)
 REFERENCES public.other_addas(adda_id,id) ON DELETE RESTRICT,
 CONSTRAINT other_adda_transactions_identity UNIQUE (adda_id,other_adda_id,id),
 CONSTRAINT other_adda_transactions_request UNIQUE (adda_id,request_id),
 CONSTRAINT other_adda_transactions_reversal_fk FOREIGN KEY (adda_id,other_adda_id,reverses_transaction_id)
 REFERENCES public.other_adda_transactions(adda_id,other_adda_id,id) ON DELETE RESTRICT,
 CONSTRAINT other_adda_transactions_event CHECK (
 (event_type='obligation' AND reverses_transaction_id IS NULL) OR
 (event_type='reversal' AND reverses_transaction_id IS NOT NULL AND reverses_transaction_id<>id))
);
CREATE UNIQUE INDEX other_adda_transactions_one_reversal
 ON public.other_adda_transactions(reverses_transaction_id) WHERE reverses_transaction_id IS NOT NULL;
CREATE INDEX other_adda_transactions_history ON public.other_adda_transactions(adda_id,other_adda_id,transaction_date,id);
CREATE INDEX other_addas_name_warning ON public.other_addas(adda_id,lower(btrim(adda_name)));
CREATE INDEX other_addas_mobile_warning ON public.other_addas(adda_id,(regexp_replace(coalesce(mobile,''),'[^0-9]','','g')));

-- Private authority helper: NULL target is allowed only for a tenant-bound caller.
CREATE FUNCTION public.ut_other_adda_authorize(p_target uuid,p_admin boolean)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_role text; v_tenant uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=auth.uid() AND is_active=true)
 THEN RAISE EXCEPTION 'active_authenticated_profile_required'; END IF;
 v_role:=public.current_user_role(); v_tenant:=public.current_user_adda_id();
 IF v_role IS NULL OR v_role NOT IN ('super_admin','adda_admin','operator') OR
 (p_admin AND v_role NOT IN ('super_admin','adda_admin')) THEN RAISE EXCEPTION 'role_not_authorized'; END IF;
 IF public.is_super_admin() THEN
  v_tenant:=coalesce(p_target,v_tenant);
 ELSE
  IF p_target IS NOT NULL AND p_target IS DISTINCT FROM v_tenant THEN RAISE EXCEPTION 'tenant_mismatch'; END IF;
 END IF;
 IF v_tenant IS NULL OR NOT EXISTS (SELECT 1 FROM public.addas WHERE id=v_tenant)
 THEN RAISE EXCEPTION 'valid_target_adda_required'; END IF;
 RETURN v_tenant;
END $fn$;

CREATE FUNCTION public.ut_other_adda_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_original public.other_adda_transactions%ROWTYPE;
BEGIN
 IF TG_TABLE_NAME='other_adda_transactions' THEN
  IF TG_OP<>'INSERT' THEN RAISE EXCEPTION 'posted_history_is_append_only'; END IF;
  PERFORM 1 FROM public.other_addas WHERE adda_id=NEW.adda_id AND id=NEW.other_adda_id AND status='active' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'active_other_adda_required'; END IF;
  IF NEW.event_type='reversal' THEN
   SELECT * INTO v_original FROM public.other_adda_transactions WHERE id=NEW.reverses_transaction_id FOR UPDATE;
   IF NOT FOUND OR v_original.event_type<>'obligation' OR v_original.adda_id<>NEW.adda_id OR
    v_original.other_adda_id<>NEW.other_adda_id OR v_original.side<>NEW.side OR v_original.amount<>NEW.amount
    OR NEW.transaction_date<v_original.transaction_date
   THEN RAISE EXCEPTION 'invalid_reversal'; END IF;
  END IF;
 ELSE
  IF TG_OP IN ('DELETE','TRUNCATE') THEN RAISE EXCEPTION 'master_history_cannot_be_deleted'; END IF;
  IF TG_OP='UPDATE' AND (NEW.id<>OLD.id OR NEW.adda_id<>OLD.adda_id OR NEW.created_at<>OLD.created_at OR NEW.created_by<>OLD.created_by)
  THEN RAISE EXCEPTION 'master_identity_is_immutable'; END IF;
  IF NEW.status='archived' AND EXISTS (
   SELECT 1 FROM public.other_adda_transactions r
   LEFT JOIN public.other_adda_transactions o ON o.id=r.reverses_transaction_id
   WHERE r.other_adda_id=NEW.id AND r.event_type='reversal' AND
   (o.id IS NULL OR o.event_type<>'obligation' OR o.adda_id<>r.adda_id OR
    o.other_adda_id<>r.other_adda_id OR o.side<>r.side OR o.amount<>r.amount OR r.transaction_date<o.transaction_date))
  THEN RAISE EXCEPTION 'invalid_reversal_state'; END IF;
  IF NEW.status='archived' AND EXISTS (
   SELECT 1 FROM public.other_adda_transactions o WHERE o.other_adda_id=NEW.id AND o.event_type='obligation'
   AND NOT EXISTS (SELECT 1 FROM public.other_adda_transactions r WHERE r.reverses_transaction_id=o.id))
  THEN RAISE EXCEPTION 'gross_obligations_outstanding'; END IF;
 END IF;
 RETURN NEW;
END $fn$;
CREATE TRIGGER other_adda_transactions_guard BEFORE INSERT OR UPDATE OR DELETE ON public.other_adda_transactions
 FOR EACH ROW EXECUTE FUNCTION public.ut_other_adda_guard();
CREATE TRIGGER other_adda_transactions_no_truncate BEFORE TRUNCATE ON public.other_adda_transactions
 FOR EACH STATEMENT EXECUTE FUNCTION public.ut_other_adda_guard();
CREATE TRIGGER other_addas_guard BEFORE INSERT OR UPDATE OR DELETE ON public.other_addas
 FOR EACH ROW EXECUTE FUNCTION public.ut_other_adda_guard();
CREATE TRIGGER other_addas_no_truncate BEFORE TRUNCATE ON public.other_addas
 FOR EACH STATEMENT EXECUTE FUNCTION public.ut_other_adda_guard();

CREATE FUNCTION public.save_other_adda(p_id uuid,p_adda_name text,p_contact_person text DEFAULT NULL,
 p_mobile text DEFAULT NULL,p_whatsapp text DEFAULT NULL,p_city text DEFAULT NULL,p_address text DEFAULT NULL,
 p_ntn_cnic text DEFAULT NULL,p_business_type text DEFAULT 'regular',p_notes text DEFAULT NULL,p_target_adda_id uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_tenant uuid; v_id uuid;
BEGIN
 v_tenant:=public.ut_other_adda_authorize(p_target_adda_id,true);
 IF p_id IS NOT NULL THEN
  PERFORM 1 FROM public.other_addas WHERE id=p_id AND adda_id=v_tenant FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'other_adda_not_in_tenant'; END IF;
 END IF;
 IF p_adda_name IS NULL OR btrim(p_adda_name)='' OR p_business_type IS NULL OR p_business_type NOT IN ('regular','one_time')
 THEN RAISE EXCEPTION 'invalid_master_payload'; END IF;
 IF p_id IS NULL THEN
  INSERT INTO public.other_addas(adda_id,adda_name,contact_person,mobile,whatsapp,city,address,ntn_cnic,business_type,notes,created_by,updated_by)
  VALUES(v_tenant,btrim(p_adda_name),p_contact_person,p_mobile,p_whatsapp,p_city,p_address,p_ntn_cnic,p_business_type,p_notes,auth.uid(),auth.uid()) RETURNING id INTO v_id;
 ELSE
  UPDATE public.other_addas SET adda_name=btrim(p_adda_name),contact_person=p_contact_person,mobile=p_mobile,
   whatsapp=p_whatsapp,city=p_city,address=p_address,ntn_cnic=p_ntn_cnic,business_type=p_business_type,notes=p_notes,
   updated_at=now(),updated_by=auth.uid() WHERE id=p_id AND adda_id=v_tenant RETURNING id INTO v_id;
 END IF;
 RETURN v_id;
END $fn$;

-- Single explicit lifecycle RPC: no implied delete and no net-zero archive test.
CREATE FUNCTION public.set_other_adda_status(p_other_adda_id uuid,p_status text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_tenant uuid;
BEGIN
 SELECT adda_id INTO v_tenant FROM public.other_addas WHERE id=p_other_adda_id;
 v_tenant:=public.ut_other_adda_authorize(v_tenant,true);
 IF p_status IS NULL OR p_status NOT IN ('active','archived') THEN RAISE EXCEPTION 'invalid_status'; END IF;
 PERFORM 1 FROM public.other_addas WHERE id=p_other_adda_id AND adda_id=v_tenant FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'other_adda_not_found'; END IF;
 UPDATE public.other_addas SET status=p_status,
 archived_at=CASE WHEN p_status='archived' THEN coalesce(archived_at,now()) ELSE NULL END,
 archived_by=CASE WHEN p_status='archived' THEN coalesce(archived_by,auth.uid()) ELSE NULL END,
 updated_at=now(),updated_by=auth.uid() WHERE id=p_other_adda_id;
 RETURN p_other_adda_id;
END $fn$;

-- Private event implementation. Entry wrappers and this helper both validate authority.
CREATE FUNCTION public.ut_other_adda_event(p_other_adda_id uuid,p_date date,p_side text,p_amount numeric,
 p_description text,p_reference_no text,p_request_id uuid,p_original uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_tenant uuid; v_row public.other_adda_transactions%ROWTYPE;
 v_old public.other_adda_transactions%ROWTYPE; v_id uuid; v_kind text;
BEGIN
 SELECT adda_id INTO v_tenant FROM public.other_addas WHERE id=p_other_adda_id;
 v_tenant:=public.ut_other_adda_authorize(v_tenant,p_original IS NOT NULL);
 IF p_request_id IS NULL OR p_date IS NULL OR p_description IS NULL OR btrim(p_description)=''
 THEN RAISE EXCEPTION 'required_event_payload'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_tenant::text||':'||p_request_id::text,0));
 PERFORM 1 FROM public.other_addas WHERE id=p_other_adda_id AND adda_id=v_tenant FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'other_adda_not_found'; END IF;
 v_kind:=CASE WHEN p_original IS NULL THEN 'obligation' ELSE 'reversal' END;
 IF p_original IS NOT NULL THEN
  SELECT * INTO v_old FROM public.other_adda_transactions WHERE id=p_original AND adda_id=v_tenant AND other_adda_id=p_other_adda_id FOR UPDATE;
  IF NOT FOUND OR v_old.event_type<>'obligation' OR p_date<v_old.transaction_date THEN RAISE EXCEPTION 'invalid_original'; END IF;
  p_side:=v_old.side; p_amount:=v_old.amount;
 END IF;
 IF p_side IS NULL OR p_side NOT IN ('receivable','payable') OR p_amount IS NULL OR p_amount<=0
 OR p_amount::text IN ('NaN','Infinity','-Infinity') OR p_amount<>round(p_amount,2) OR p_amount>=10000000000000000
 THEN RAISE EXCEPTION 'invalid_side_or_amount'; END IF;
 SELECT * INTO v_row FROM public.other_adda_transactions WHERE adda_id=v_tenant AND request_id=p_request_id;
 IF FOUND THEN
  IF v_row.other_adda_id IS DISTINCT FROM p_other_adda_id OR v_row.transaction_date IS DISTINCT FROM p_date OR
  v_row.side IS DISTINCT FROM p_side OR v_row.amount IS DISTINCT FROM p_amount OR v_row.description IS DISTINCT FROM btrim(p_description)
  OR v_row.reference_no IS DISTINCT FROM p_reference_no OR v_row.event_type IS DISTINCT FROM v_kind
  OR v_row.reverses_transaction_id IS DISTINCT FROM p_original OR v_row.created_by IS DISTINCT FROM auth.uid()
  THEN RAISE EXCEPTION 'idempotency_payload_mismatch'; END IF;
  RETURN v_row.id;
 END IF;
 IF NOT EXISTS (SELECT 1 FROM public.other_addas WHERE id=p_other_adda_id AND status='active') THEN RAISE EXCEPTION 'active_other_adda_required'; END IF;
 IF p_original IS NOT NULL AND EXISTS (SELECT 1 FROM public.other_adda_transactions WHERE reverses_transaction_id=p_original)
 THEN RAISE EXCEPTION 'already_reversed'; END IF;
 INSERT INTO public.other_adda_transactions(adda_id,other_adda_id,transaction_date,side,amount,description,reference_no,event_type,request_id,reverses_transaction_id,created_by)
 VALUES(v_tenant,p_other_adda_id,p_date,p_side,p_amount,btrim(p_description),p_reference_no,v_kind,p_request_id,p_original,auth.uid()) RETURNING id INTO v_id;
 RETURN v_id;
END $fn$;
CREATE FUNCTION public.post_other_adda_obligation(p_other_adda_id uuid,p_transaction_date date,p_side text,p_amount numeric,
 p_description text,p_request_id uuid,p_reference_no text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_tenant uuid;
BEGIN
 SELECT adda_id INTO v_tenant FROM public.other_addas WHERE id=p_other_adda_id;
 PERFORM public.ut_other_adda_authorize(v_tenant,false);
 RETURN public.ut_other_adda_event(p_other_adda_id,p_transaction_date,p_side,p_amount,p_description,p_reference_no,p_request_id,NULL);
END $fn$;
CREATE FUNCTION public.reverse_other_adda_obligation(p_transaction_id uuid,p_transaction_date date,p_reason text,p_request_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_master uuid; v_tenant uuid;
BEGIN
 SELECT other_adda_id,adda_id INTO v_master,v_tenant FROM public.other_adda_transactions WHERE id=p_transaction_id;
 PERFORM public.ut_other_adda_authorize(v_tenant,true);
 IF v_master IS NULL THEN RAISE EXCEPTION 'original_not_found'; END IF;
 RETURN public.ut_other_adda_event(v_master,p_transaction_date,NULL,NULL,p_reason,NULL,p_request_id,p_transaction_id);
END $fn$;

CREATE FUNCTION public.find_other_adda_duplicates(p_adda_name text,p_mobile text DEFAULT NULL,p_city text DEFAULT NULL,p_target_adda_id uuid DEFAULT NULL)
RETURNS TABLE(id uuid,adda_name text,mobile text,city text,status text,name_match boolean,mobile_match boolean,city_match boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_tenant uuid;
BEGIN
 v_tenant:=public.ut_other_adda_authorize(p_target_adda_id,false);
 RETURN QUERY SELECT m.id,m.adda_name,m.mobile,m.city,m.status,
 coalesce(lower(btrim(m.adda_name))=nullif(lower(btrim(p_adda_name)),''),false),
 coalesce(nullif(regexp_replace(coalesce(m.mobile,''),'[^0-9]','','g'),'')=nullif(regexp_replace(coalesce(p_mobile,''),'[^0-9]','','g'),''),false),
 coalesce(nullif(lower(btrim(m.city)),'')=nullif(lower(btrim(p_city)),''),false)
 FROM public.other_addas m WHERE m.adda_id=v_tenant AND (
 lower(btrim(m.adda_name))=nullif(lower(btrim(p_adda_name)),'') OR
 nullif(regexp_replace(coalesce(m.mobile,''),'[^0-9]','','g'),'')=nullif(regexp_replace(coalesce(p_mobile,''),'[^0-9]','','g'),'')) ORDER BY m.adda_name,m.id;
END $fn$;
CREATE FUNCTION public.get_other_adda_balances(p_target_adda_id uuid DEFAULT NULL)
RETURNS TABLE(other_adda_id uuid,gross_receivable numeric,gross_payable numeric,net numeric,obligation_count bigint,reversal_count bigint,effective_obligation_count bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_tenant uuid;
BEGIN
 v_tenant:=public.ut_other_adda_authorize(p_target_adda_id,false);
 RETURN QUERY SELECT m.id,
 coalesce(sum(CASE WHEN t.side='receivable' THEN CASE WHEN t.event_type='reversal' THEN -t.amount ELSE t.amount END ELSE 0 END),0),
 coalesce(sum(CASE WHEN t.side='payable' THEN CASE WHEN t.event_type='reversal' THEN -t.amount ELSE t.amount END ELSE 0 END),0),
 coalesce(sum(CASE WHEN t.side='receivable' THEN 1 ELSE -1 END * CASE WHEN t.event_type='reversal' THEN -t.amount ELSE t.amount END),0),
 count(t.id) FILTER(WHERE t.event_type='obligation'),count(t.id) FILTER(WHERE t.event_type='reversal'),
 count(t.id) FILTER(WHERE t.event_type='obligation')-count(t.id) FILTER(WHERE t.event_type='reversal')
 FROM public.other_addas m LEFT JOIN public.other_adda_transactions t ON t.other_adda_id=m.id AND t.adda_id=m.adda_id
 WHERE m.adda_id=v_tenant GROUP BY m.id;
END $fn$;

ALTER TABLE public.other_addas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.other_adda_transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY other_addas_read ON public.other_addas FOR SELECT TO authenticated USING (
 public.current_user_role() IN ('super_admin','adda_admin','operator') AND
 EXISTS(SELECT 1 FROM public.profiles p WHERE p.id=auth.uid() AND p.is_active=true) AND
 (adda_id=public.current_user_adda_id() OR public.is_super_admin()));
CREATE POLICY other_adda_transactions_read ON public.other_adda_transactions FOR SELECT TO authenticated USING (
 public.current_user_role() IN ('super_admin','adda_admin','operator') AND
 EXISTS(SELECT 1 FROM public.profiles p WHERE p.id=auth.uid() AND p.is_active=true) AND
 (adda_id=public.current_user_adda_id() OR public.is_super_admin()));
REVOKE ALL ON public.other_addas,public.other_adda_transactions FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.other_addas,public.other_adda_transactions TO authenticated;
-- Service credentials are not browser authority: no direct DML or RPC grants.
-- Owner-controlled maintenance is explicit; super-admin reads are intentionally global.
REVOKE ALL ON FUNCTION public.ut_other_adda_authorize(uuid,boolean),public.ut_other_adda_guard(),
 public.ut_other_adda_event(uuid,date,text,numeric,text,text,uuid,uuid),
 public.save_other_adda(uuid,text,text,text,text,text,text,text,text,text,uuid),
 public.set_other_adda_status(uuid,text),public.post_other_adda_obligation(uuid,date,text,numeric,text,uuid,text),
 public.reverse_other_adda_obligation(uuid,date,text,uuid),public.find_other_adda_duplicates(text,text,text,uuid),
 public.get_other_adda_balances(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_other_adda(uuid,text,text,text,text,text,text,text,text,text,uuid),
 public.set_other_adda_status(uuid,text),public.post_other_adda_obligation(uuid,date,text,numeric,text,uuid,text),
 public.reverse_other_adda_obligation(uuid,date,text,uuid),public.find_other_adda_duplicates(text,text,text,uuid),
 public.get_other_adda_balances(uuid) TO authenticated;
COMMIT;
