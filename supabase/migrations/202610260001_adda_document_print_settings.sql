BEGIN;

DO $print_settings_preconditions$
BEGIN
  IF pg_catalog.to_regclass('public.adda_document_print_settings') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.get_adda_document_print_settings(uuid)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.save_adda_document_print_setting(uuid,text,text,text,text,numeric,numeric,numeric,numeric,boolean,boolean,boolean,boolean,boolean)') IS NOT NULL THEN
    RAISE EXCEPTION 'PRINT_SETTINGS_PRECONDITION_NAME_COLLISION';
  END IF;

  IF pg_catalog.to_regclass('public.profiles') IS NULL
     OR pg_catalog.to_regclass('public.addas') IS NULL
     OR pg_catalog.to_regprocedure('auth.uid()') IS NULL THEN
    RAISE EXCEPTION 'PRINT_SETTINGS_PRECONDITION_REQUIRED_AUTH_RELATION_MISSING';
  END IF;

  IF NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_attribute
       WHERE attrelid = 'public.profiles'::pg_catalog.regclass
         AND attname = 'id' AND atttypid = 'uuid'::pg_catalog.regtype AND NOT attisdropped
     ) OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_attribute
       WHERE attrelid = 'public.profiles'::pg_catalog.regclass
         AND attname = 'adda_id' AND atttypid = 'uuid'::pg_catalog.regtype AND NOT attisdropped
     ) OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_attribute
       WHERE attrelid = 'public.profiles'::pg_catalog.regclass
         AND attname = 'role' AND atttypid = 'text'::pg_catalog.regtype AND NOT attisdropped
     ) OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_attribute
       WHERE attrelid = 'public.profiles'::pg_catalog.regclass
         AND attname = 'is_active' AND atttypid = 'boolean'::pg_catalog.regtype AND NOT attisdropped
     ) OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_attribute
       WHERE attrelid = 'public.addas'::pg_catalog.regclass
         AND attname = 'id' AND atttypid = 'uuid'::pg_catalog.regtype AND NOT attisdropped
     ) THEN
    RAISE EXCEPTION 'PRINT_SETTINGS_PRECONDITION_AUTH_SCHEMA_DRIFT';
  END IF;

  IF NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_constraint AS constraint_row
       JOIN pg_catalog.pg_attribute AS attribute_row
         ON attribute_row.attrelid = constraint_row.conrelid
        AND attribute_row.attname = 'id'
        AND attribute_row.attnum = ANY(constraint_row.conkey)
       WHERE constraint_row.conrelid = 'public.profiles'::pg_catalog.regclass
         AND constraint_row.contype IN ('p', 'u')
         AND constraint_row.conkey = ARRAY[attribute_row.attnum]::smallint[]
     ) OR NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_constraint AS constraint_row
       JOIN pg_catalog.pg_attribute AS attribute_row
         ON attribute_row.attrelid = constraint_row.conrelid
        AND attribute_row.attname = 'id'
        AND attribute_row.attnum = ANY(constraint_row.conkey)
       WHERE constraint_row.conrelid = 'public.addas'::pg_catalog.regclass
         AND constraint_row.contype IN ('p', 'u')
         AND constraint_row.conkey = ARRAY[attribute_row.attnum]::smallint[]
     ) THEN
    RAISE EXCEPTION 'PRINT_SETTINGS_PRECONDITION_AUTH_KEY_NOT_UNIQUE';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'anon')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'authenticated')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'service_role') THEN
    RAISE EXCEPTION 'PRINT_SETTINGS_PRECONDITION_REQUIRED_ROLE_MISSING';
  END IF;
END;
$print_settings_preconditions$;

CREATE TABLE public.adda_document_print_settings (
  adda_id uuid NOT NULL REFERENCES public.addas(id) ON DELETE CASCADE,
  document_type text NOT NULL,
  template_id text NOT NULL DEFAULT 'traditional_pad',
  paper_size text NOT NULL DEFAULT 'A4',
  orientation text NOT NULL DEFAULT 'portrait',
  margin_top_mm numeric(4,1) NOT NULL DEFAULT 10.0,
  margin_right_mm numeric(4,1) NOT NULL DEFAULT 10.0,
  margin_bottom_mm numeric(4,1) NOT NULL DEFAULT 10.0,
  margin_left_mm numeric(4,1) NOT NULL DEFAULT 10.0,
  show_logo boolean NOT NULL DEFAULT true,
  show_address boolean NOT NULL DEFAULT true,
  show_phone boolean NOT NULL DEFAULT true,
  show_signatures boolean NOT NULL DEFAULT true,
  show_stamp boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT pg_catalog.now(),
  updated_at timestamp with time zone NOT NULL DEFAULT pg_catalog.now(),
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  CONSTRAINT adda_document_print_settings_pkey PRIMARY KEY (adda_id, document_type),
  CONSTRAINT adda_document_print_settings_document_type_check CHECK (document_type IN (
    'bilty', 'bilty_chakkar', 'loading', 'packing_slip', 'voucher', 'parchi',
    'cashbook', 'customer_ledger', 'party_ledger', 'broker_ledger', 'driver_ledger',
    'owner_ledger', 'vehicle_ledger', 'vehicle_monthly_hisab', 'owner_gari_account',
    'adda_account', 'other_adda_receipt', 'payment_receipt', 'diesel', 'petrol_pump',
    'oil', 'tyre', 'workshop', 'vehicle_document', 'employee', 'reports', 'audit_log'
  )),
  CONSTRAINT adda_document_print_settings_template_id_check CHECK (template_id IN (
    'traditional_pad', 'modern_professional', 'compact_pad', 'detailed_a4'
  )),
  CONSTRAINT adda_document_print_settings_paper_size_check CHECK (paper_size IN ('A4', 'A5')),
  CONSTRAINT adda_document_print_settings_orientation_check CHECK (orientation IN ('portrait', 'landscape')),
  CONSTRAINT adda_document_print_settings_margin_top_check CHECK (
    margin_top_mm::text NOT IN ('NaN', 'Infinity', '-Infinity') AND margin_top_mm BETWEEN 0 AND 30
  ),
  CONSTRAINT adda_document_print_settings_margin_right_check CHECK (
    margin_right_mm::text NOT IN ('NaN', 'Infinity', '-Infinity') AND margin_right_mm BETWEEN 0 AND 30
  ),
  CONSTRAINT adda_document_print_settings_margin_bottom_check CHECK (
    margin_bottom_mm::text NOT IN ('NaN', 'Infinity', '-Infinity') AND margin_bottom_mm BETWEEN 0 AND 30
  ),
  CONSTRAINT adda_document_print_settings_margin_left_check CHECK (
    margin_left_mm::text NOT IN ('NaN', 'Infinity', '-Infinity') AND margin_left_mm BETWEEN 0 AND 30
  )
);

ALTER TABLE public.adda_document_print_settings ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE public.adda_document_print_settings FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.adda_document_print_settings TO service_role;

CREATE FUNCTION public.get_adda_document_print_settings(p_adda_id uuid)
RETURNS SETOF public.adda_document_print_settings
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $get_adda_document_print_settings$
DECLARE
  v_actor_id uuid;
  v_profile_role text;
  v_profile_adda_id uuid;
  v_profile_active boolean;
BEGIN
  v_actor_id := auth.uid();
  IF v_actor_id IS NULL OR p_adda_id IS NULL THEN
    RAISE EXCEPTION 'PRINT_SETTINGS_ACCESS_DENIED' USING ERRCODE = '42501';
  END IF;

  SELECT profile.role, profile.adda_id, profile.is_active
  INTO v_profile_role, v_profile_adda_id, v_profile_active
  FROM public.profiles AS profile
  WHERE profile.id = v_actor_id;

  IF NOT FOUND OR v_profile_active IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'PRINT_SETTINGS_ACTIVE_PROFILE_REQUIRED' USING ERRCODE = '42501';
  END IF;

  IF v_profile_role IS DISTINCT FROM 'super_admin'
     AND NOT (
       (v_profile_role IS NOT DISTINCT FROM 'adda_admin'
        OR v_profile_role IS NOT DISTINCT FROM 'operator')
       AND v_profile_adda_id IS NOT DISTINCT FROM p_adda_id
     ) THEN
    RAISE EXCEPTION 'PRINT_SETTINGS_ACCESS_DENIED' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.addas AS adda WHERE adda.id = p_adda_id) THEN
    RAISE EXCEPTION 'PRINT_SETTINGS_TARGET_ADDA_NOT_FOUND' USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  SELECT setting_row.*
  FROM public.adda_document_print_settings AS setting_row
  WHERE setting_row.adda_id = p_adda_id
  ORDER BY setting_row.document_type;
END;
$get_adda_document_print_settings$;

CREATE FUNCTION public.save_adda_document_print_setting(
  p_adda_id uuid,
  p_document_type text,
  p_template_id text,
  p_paper_size text,
  p_orientation text,
  p_margin_top_mm numeric,
  p_margin_right_mm numeric,
  p_margin_bottom_mm numeric,
  p_margin_left_mm numeric,
  p_show_logo boolean,
  p_show_address boolean,
  p_show_phone boolean,
  p_show_signatures boolean,
  p_show_stamp boolean
)
RETURNS public.adda_document_print_settings
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $save_adda_document_print_setting$
DECLARE
  v_actor_id uuid;
  v_profile_role text;
  v_profile_adda_id uuid;
  v_profile_active boolean;
  v_saved public.adda_document_print_settings%ROWTYPE;
BEGIN
  v_actor_id := auth.uid();
  IF v_actor_id IS NULL OR p_adda_id IS NULL THEN
    RAISE EXCEPTION 'PRINT_SETTINGS_ACCESS_DENIED' USING ERRCODE = '42501';
  END IF;

  SELECT profile.role, profile.adda_id, profile.is_active
  INTO v_profile_role, v_profile_adda_id, v_profile_active
  FROM public.profiles AS profile
  WHERE profile.id = v_actor_id
  FOR SHARE;

  IF NOT FOUND OR v_profile_active IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'PRINT_SETTINGS_ACTIVE_PROFILE_REQUIRED' USING ERRCODE = '42501';
  END IF;

  IF v_profile_role IS DISTINCT FROM 'super_admin'
     AND NOT (
       v_profile_role IS NOT DISTINCT FROM 'adda_admin'
       AND v_profile_adda_id IS NOT DISTINCT FROM p_adda_id
     ) THEN
    RAISE EXCEPTION 'PRINT_SETTINGS_MANAGE_DENIED' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.addas AS adda WHERE adda.id = p_adda_id) THEN
    RAISE EXCEPTION 'PRINT_SETTINGS_TARGET_ADDA_NOT_FOUND' USING ERRCODE = '22023';
  END IF;

  IF p_margin_top_mm IS NULL OR p_margin_right_mm IS NULL
     OR p_margin_bottom_mm IS NULL OR p_margin_left_mm IS NULL
     OR p_margin_top_mm::text IN ('NaN', 'Infinity', '-Infinity')
     OR p_margin_right_mm::text IN ('NaN', 'Infinity', '-Infinity')
     OR p_margin_bottom_mm::text IN ('NaN', 'Infinity', '-Infinity')
     OR p_margin_left_mm::text IN ('NaN', 'Infinity', '-Infinity') THEN
    RAISE EXCEPTION 'PRINT_SETTINGS_INVALID_MARGIN' USING ERRCODE = '22023';
  END IF;

  IF p_margin_top_mm < 0 OR p_margin_top_mm > 30 OR p_margin_top_mm * 10 <> pg_catalog.trunc(p_margin_top_mm * 10)
     OR p_margin_right_mm < 0 OR p_margin_right_mm > 30 OR p_margin_right_mm * 10 <> pg_catalog.trunc(p_margin_right_mm * 10)
     OR p_margin_bottom_mm < 0 OR p_margin_bottom_mm > 30 OR p_margin_bottom_mm * 10 <> pg_catalog.trunc(p_margin_bottom_mm * 10)
     OR p_margin_left_mm < 0 OR p_margin_left_mm > 30 OR p_margin_left_mm * 10 <> pg_catalog.trunc(p_margin_left_mm * 10) THEN
    RAISE EXCEPTION 'PRINT_SETTINGS_INVALID_MARGIN' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.adda_document_print_settings AS settings (
    adda_id, document_type, template_id, paper_size, orientation,
    margin_top_mm, margin_right_mm, margin_bottom_mm, margin_left_mm,
    show_logo, show_address, show_phone, show_signatures, show_stamp,
    created_by, updated_by
  ) VALUES (
    p_adda_id, p_document_type, p_template_id, p_paper_size, p_orientation,
    p_margin_top_mm, p_margin_right_mm, p_margin_bottom_mm, p_margin_left_mm,
    p_show_logo, p_show_address, p_show_phone, p_show_signatures, p_show_stamp,
    v_actor_id, v_actor_id
  )
  ON CONFLICT (adda_id, document_type) DO UPDATE SET
    template_id = EXCLUDED.template_id,
    paper_size = EXCLUDED.paper_size,
    orientation = EXCLUDED.orientation,
    margin_top_mm = EXCLUDED.margin_top_mm,
    margin_right_mm = EXCLUDED.margin_right_mm,
    margin_bottom_mm = EXCLUDED.margin_bottom_mm,
    margin_left_mm = EXCLUDED.margin_left_mm,
    show_logo = EXCLUDED.show_logo,
    show_address = EXCLUDED.show_address,
    show_phone = EXCLUDED.show_phone,
    show_signatures = EXCLUDED.show_signatures,
    show_stamp = EXCLUDED.show_stamp,
    updated_at = pg_catalog.clock_timestamp(),
    updated_by = v_actor_id
  RETURNING settings.* INTO v_saved;

  RETURN v_saved;
END;
$save_adda_document_print_setting$;

REVOKE ALL PRIVILEGES ON FUNCTION public.get_adda_document_print_settings(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_adda_document_print_settings(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_adda_document_print_settings(uuid) TO service_role;
REVOKE ALL PRIVILEGES ON FUNCTION public.save_adda_document_print_setting(uuid,text,text,text,text,numeric,numeric,numeric,numeric,boolean,boolean,boolean,boolean,boolean) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.save_adda_document_print_setting(uuid,text,text,text,text,numeric,numeric,numeric,numeric,boolean,boolean,boolean,boolean,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_adda_document_print_setting(uuid,text,text,text,text,numeric,numeric,numeric,numeric,boolean,boolean,boolean,boolean,boolean) TO service_role;

COMMIT;
