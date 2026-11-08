BEGIN;

DO $preconditions$
BEGIN
  IF pg_catalog.to_regclass('storage.buckets') IS NULL
     OR pg_catalog.to_regclass('storage.objects') IS NULL THEN
    RAISE EXCEPTION 'ADDA_LOGO_STORAGE_SCHEMA_MISSING';
  END IF;

  IF pg_catalog.to_regclass('public.profiles') IS NULL
     OR pg_catalog.to_regclass('public.addas') IS NULL THEN
    RAISE EXCEPTION 'ADDA_LOGO_AUTHORIZATION_TABLE_MISSING';
  END IF;

  IF pg_catalog.to_regclass('public.company_settings') IS NULL
     OR pg_catalog.to_regprocedure('auth.uid()') IS NULL
     OR pg_catalog.to_regprocedure('auth.role()') IS NULL THEN
    RAISE EXCEPTION 'ADDA_LOGO_SETTINGS_OR_AUTH_HELPER_MISSING';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute AS a
    WHERE a.attrelid = 'public.profiles'::pg_catalog.regclass
      AND a.attname = 'is_active' AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute AS a
    WHERE a.attrelid = 'public.profiles'::pg_catalog.regclass
      AND a.attname = 'role' AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute AS a
    WHERE a.attrelid = 'public.profiles'::pg_catalog.regclass
      AND a.attname = 'adda_id' AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute AS a
    WHERE a.attrelid = 'public.addas'::pg_catalog.regclass
      AND a.attname = 'id' AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute AS a
    WHERE a.attrelid = 'public.company_settings'::pg_catalog.regclass
      AND a.attname = 'logo_url' AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute AS a
    WHERE a.attrelid = 'storage.objects'::pg_catalog.regclass
      AND a.attname = 'metadata' AND a.atttypid = 'jsonb'::pg_catalog.regtype
      AND NOT a.attisdropped
  ) THEN
    RAISE EXCEPTION 'ADDA_LOGO_AUTHORIZATION_SCHEMA_MISMATCH';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS c
    WHERE c.oid = 'storage.objects'::pg_catalog.regclass
      AND c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'ADDA_LOGO_STORAGE_RLS_DISABLED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS c
    WHERE c.oid = 'public.company_settings'::pg_catalog.regclass
      AND c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'ADDA_LOGO_SETTINGS_RLS_DISABLED';
  END IF;
  IF NOT pg_catalog.has_table_privilege('authenticated', 'public.company_settings', 'UPDATE')
     OR NOT pg_catalog.has_table_privilege('service_role', 'public.company_settings', 'UPDATE') THEN
    RAISE EXCEPTION 'ADDA_LOGO_SETTINGS_UPDATE_ACCESS_MISSING';
  END IF;
END;
$preconditions$;

DO $bucket_ownership$
DECLARE
  v_existing_bucket boolean;
  v_package_policy_count integer;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM storage.buckets AS b WHERE b.id = 'adda-logos'
  ) INTO v_existing_bucket;

  IF v_existing_bucket THEN
    SELECT count(*)::integer INTO v_package_policy_count
    FROM pg_catalog.pg_policies AS p
    WHERE p.schemaname = 'storage'
      AND p.tablename = 'objects'
      AND p.policyname IN (
        'adda_logos_read_own_active_adda',
        'adda_logos_insert_admin_own_adda',
        'adda_logos_delete_admin_own_adda',
        'adda_logos_guard_select_scope',
        'adda_logos_guard_insert_scope',
        'adda_logos_guard_update_denied',
        'adda_logos_guard_delete_scope'
      );
    IF v_package_policy_count <> 7 THEN
      RAISE EXCEPTION 'ADDA_LOGO_BUCKET_ALREADY_EXISTS_UNOWNED';
    END IF;
  END IF;
END;
$bucket_ownership$;

INSERT INTO storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
VALUES (
  'adda-logos', 'adda-logos', false, 2097152,
  ARRAY['image/png', 'image/jpeg', 'image/webp']::text[]
)
ON CONFLICT (id) DO NOTHING;

DO $bucket_contract$
DECLARE
  v_public boolean;
  v_file_size_limit bigint;
  v_allowed_mime_types text[];
BEGIN
  SELECT b.public, b.file_size_limit, b.allowed_mime_types
  INTO v_public, v_file_size_limit, v_allowed_mime_types
  FROM storage.buckets AS b
  WHERE b.id = 'adda-logos';

  IF NOT FOUND
     OR v_public IS DISTINCT FROM false
     OR v_file_size_limit IS DISTINCT FROM 2097152
     OR v_allowed_mime_types IS NULL
     OR pg_catalog.cardinality(v_allowed_mime_types) <> 3
     OR NOT (v_allowed_mime_types @> ARRAY['image/png', 'image/jpeg', 'image/webp']::text[]) THEN
    RAISE EXCEPTION 'ADDA_LOGO_BUCKET_CONTRACT_MISMATCH';
  END IF;
END;
$bucket_contract$;

CREATE OR REPLACE FUNCTION public.guard_company_settings_logo_url_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $logo_guard$
DECLARE
  v_user_id uuid := auth.uid();
  v_role text;
  v_profile_adda_id uuid;
  v_is_active boolean;
  v_object_path text;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.logo_url IS NOT DISTINCT FROM OLD.logo_url THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' AND NEW.logo_url IS NULL THEN
    RETURN NEW;
  END IF;
  IF auth.role() = 'service_role' THEN
    RETURN NEW;
  END IF;

  SELECT p.role, p.adda_id, p.is_active
  INTO v_role, v_profile_adda_id, v_is_active
  FROM public.profiles AS p
  WHERE p.id = v_user_id;

  IF v_user_id IS NULL OR NOT coalesce(v_is_active, false) THEN
    RAISE EXCEPTION 'ADDA_LOGO_ACTIVE_PROFILE_REQUIRED' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id = NEW.adda_id) THEN
    RAISE EXCEPTION 'ADDA_LOGO_TARGET_ADDA_INVALID' USING ERRCODE = '42501';
  END IF;
  IF v_role IS DISTINCT FROM 'super_admin'
     AND (v_role IS DISTINCT FROM 'adda_admin'
          OR v_profile_adda_id IS DISTINCT FROM NEW.adda_id) THEN
    RAISE EXCEPTION 'ADDA_LOGO_CHANGE_NOT_AUTHORIZED' USING ERRCODE = '42501';
  END IF;
  IF NEW.logo_url IS NOT NULL THEN
    IF NEW.logo_url !~ (
      '^storage://adda-logos/' || NEW.adda_id::text ||
      '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}[.](png|jpg|jpeg|webp)$'
    ) THEN
      RAISE EXCEPTION 'ADDA_LOGO_REFERENCE_INVALID' USING ERRCODE = '22023';
    END IF;
    v_object_path := pg_catalog.substr(NEW.logo_url, pg_catalog.length('storage://adda-logos/') + 1);
    IF NOT EXISTS (
      SELECT 1 FROM storage.objects AS logo_object
      WHERE logo_object.bucket_id = 'adda-logos'
        AND logo_object.name = v_object_path
    ) THEN
      RAISE EXCEPTION 'ADDA_LOGO_OBJECT_NOT_FOUND' USING ERRCODE = '22023';
    END IF;
  END IF;
  RETURN NEW;
END;
$logo_guard$;

ALTER FUNCTION public.guard_company_settings_logo_url_write() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.guard_company_settings_logo_url_write() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.guard_company_settings_logo_url_write() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.guard_company_settings_logo_url_write() TO service_role;

DROP TRIGGER IF EXISTS company_settings_logo_url_guard_insert ON public.company_settings;
DROP TRIGGER IF EXISTS company_settings_logo_url_guard_update ON public.company_settings;
CREATE TRIGGER company_settings_logo_url_guard_insert
BEFORE INSERT ON public.company_settings
FOR EACH ROW
WHEN (NEW.logo_url IS NOT NULL)
EXECUTE FUNCTION public.guard_company_settings_logo_url_write();
CREATE TRIGGER company_settings_logo_url_guard_update
BEFORE UPDATE OF logo_url ON public.company_settings
FOR EACH ROW
EXECUTE FUNCTION public.guard_company_settings_logo_url_write();

DROP POLICY IF EXISTS adda_logos_read_own_active_adda ON storage.objects;
DROP POLICY IF EXISTS adda_logos_insert_admin_own_adda ON storage.objects;
DROP POLICY IF EXISTS adda_logos_delete_admin_own_adda ON storage.objects;
DROP POLICY IF EXISTS adda_logos_guard_select_scope ON storage.objects;
DROP POLICY IF EXISTS adda_logos_guard_insert_scope ON storage.objects;
DROP POLICY IF EXISTS adda_logos_guard_update_denied ON storage.objects;
DROP POLICY IF EXISTS adda_logos_guard_delete_scope ON storage.objects;

CREATE POLICY adda_logos_read_own_active_adda
ON storage.objects
AS PERMISSIVE
FOR SELECT
TO authenticated
USING (
  bucket_id = 'adda-logos'
  AND name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}[.](png|jpg|jpeg|webp)$'
  AND ((name ~ '[.]png$' AND metadata->>'mimetype' = 'image/png')
    OR (name ~ '[.]jpe?g$' AND metadata->>'mimetype' = 'image/jpeg')
    OR (name ~ '[.]webp$' AND metadata->>'mimetype' = 'image/webp'))
  AND EXISTS (
    SELECT 1
    FROM public.profiles AS profile_row
    JOIN public.addas AS adda_row
      ON adda_row.id::text = pg_catalog.split_part(storage.objects.name, '/', 1)
    WHERE profile_row.id = auth.uid()
      AND profile_row.is_active IS TRUE
      AND (
        profile_row.role = 'super_admin'
        OR (
          profile_row.role IN ('adda_admin', 'operator')
          AND profile_row.adda_id = adda_row.id
        )
      )
  )
);

CREATE POLICY adda_logos_insert_admin_own_adda
ON storage.objects
AS PERMISSIVE
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'adda-logos'
  AND name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}[.](png|jpg|jpeg|webp)$'
  AND ((name ~ '[.]png$' AND metadata->>'mimetype' = 'image/png')
    OR (name ~ '[.]jpe?g$' AND metadata->>'mimetype' = 'image/jpeg')
    OR (name ~ '[.]webp$' AND metadata->>'mimetype' = 'image/webp'))
  AND EXISTS (
    SELECT 1
    FROM public.profiles AS profile_row
    JOIN public.addas AS adda_row
      ON adda_row.id::text = pg_catalog.split_part(storage.objects.name, '/', 1)
    WHERE profile_row.id = auth.uid()
      AND profile_row.is_active IS TRUE
      AND (
        profile_row.role = 'super_admin'
        OR (
          profile_row.role = 'adda_admin'
          AND profile_row.adda_id = adda_row.id
        )
      )
  )
);

CREATE POLICY adda_logos_delete_admin_own_adda
ON storage.objects
AS PERMISSIVE
FOR DELETE
TO authenticated
USING (
  bucket_id = 'adda-logos'
  AND name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}[.](png|jpg|jpeg|webp)$'
  AND ((name ~ '[.]png$' AND metadata->>'mimetype' = 'image/png')
    OR (name ~ '[.]jpe?g$' AND metadata->>'mimetype' = 'image/jpeg')
    OR (name ~ '[.]webp$' AND metadata->>'mimetype' = 'image/webp'))
  AND EXISTS (
    SELECT 1
    FROM public.profiles AS profile_row
    JOIN public.addas AS adda_row
      ON adda_row.id::text = pg_catalog.split_part(storage.objects.name, '/', 1)
    WHERE profile_row.id = auth.uid()
      AND profile_row.is_active IS TRUE
      AND (
        profile_row.role = 'super_admin'
        OR (
          profile_row.role = 'adda_admin'
          AND profile_row.adda_id = adda_row.id
        )
      )
  )
);

-- Restrictive guards constrain any existing shared permissive Storage policy
-- for this bucket without changing policies or grants used by other buckets.
CREATE POLICY adda_logos_guard_select_scope
ON storage.objects
AS RESTRICTIVE
FOR SELECT
TO public
USING (
  bucket_id <> 'adda-logos'
  OR (
    name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}[.](png|jpg|jpeg|webp)$'
    AND ((name ~ '[.]png$' AND metadata->>'mimetype' = 'image/png')
      OR (name ~ '[.]jpe?g$' AND metadata->>'mimetype' = 'image/jpeg')
      OR (name ~ '[.]webp$' AND metadata->>'mimetype' = 'image/webp'))
    AND EXISTS (
      SELECT 1 FROM public.profiles AS profile_row
      JOIN public.addas AS adda_row
        ON adda_row.id::text = pg_catalog.split_part(storage.objects.name, '/', 1)
      WHERE profile_row.id = auth.uid()
        AND profile_row.is_active IS TRUE
        AND (
          profile_row.role = 'super_admin'
          OR (profile_row.role IN ('adda_admin', 'operator') AND profile_row.adda_id = adda_row.id)
        )
    )
  )
);

CREATE POLICY adda_logos_guard_insert_scope
ON storage.objects
AS RESTRICTIVE
FOR INSERT
TO public
WITH CHECK (
  bucket_id <> 'adda-logos'
  OR (
    name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}[.](png|jpg|jpeg|webp)$'
    AND ((name ~ '[.]png$' AND metadata->>'mimetype' = 'image/png')
      OR (name ~ '[.]jpe?g$' AND metadata->>'mimetype' = 'image/jpeg')
      OR (name ~ '[.]webp$' AND metadata->>'mimetype' = 'image/webp'))
    AND EXISTS (
      SELECT 1 FROM public.profiles AS profile_row
      JOIN public.addas AS adda_row
        ON adda_row.id::text = pg_catalog.split_part(storage.objects.name, '/', 1)
      WHERE profile_row.id = auth.uid()
        AND profile_row.is_active IS TRUE
        AND (
          profile_row.role = 'super_admin'
          OR (profile_row.role = 'adda_admin' AND profile_row.adda_id = adda_row.id)
        )
    )
  )
);

CREATE POLICY adda_logos_guard_update_denied
ON storage.objects
AS RESTRICTIVE
FOR UPDATE
TO public
USING (bucket_id <> 'adda-logos')
WITH CHECK (bucket_id <> 'adda-logos');

CREATE POLICY adda_logos_guard_delete_scope
ON storage.objects
AS RESTRICTIVE
FOR DELETE
TO public
USING (
  bucket_id <> 'adda-logos'
  OR (
    name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}[.](png|jpg|jpeg|webp)$'
    AND ((name ~ '[.]png$' AND metadata->>'mimetype' = 'image/png')
      OR (name ~ '[.]jpe?g$' AND metadata->>'mimetype' = 'image/jpeg')
      OR (name ~ '[.]webp$' AND metadata->>'mimetype' = 'image/webp'))
    AND EXISTS (
      SELECT 1 FROM public.profiles AS profile_row
      JOIN public.addas AS adda_row
        ON adda_row.id::text = pg_catalog.split_part(storage.objects.name, '/', 1)
      WHERE profile_row.id = auth.uid()
        AND profile_row.is_active IS TRUE
        AND (
          profile_row.role = 'super_admin'
          OR (profile_row.role = 'adda_admin' AND profile_row.adda_id = adda_row.id)
        )
    )
  )
);

COMMIT;
