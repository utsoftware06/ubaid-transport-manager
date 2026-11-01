BEGIN;

DO $preflight$
BEGIN
  IF pg_catalog.to_regclass('public.bookings') IS NULL THEN
    RAISE EXCEPTION 'BILTY_DETAIN_CHARGES: public.bookings is missing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('id', 'uuid'),
      ('adda_id', 'uuid'),
      ('vehicle_freight', 'numeric'),
      ('broker_commission', 'numeric'),
      ('overweight_charges', 'numeric'),
      ('lolo_charges', 'numeric')
    ) AS expected(column_name, expected_type)
    LEFT JOIN information_schema.columns AS actual
      ON actual.table_schema = 'public'
     AND actual.table_name = 'bookings'
     AND actual.column_name = expected.column_name
    WHERE actual.column_name IS NULL
       OR actual.udt_name IS DISTINCT FROM expected.expected_type
  ) THEN
    RAISE EXCEPTION 'BILTY_DETAIN_CHARGES: existing Bilty freight columns have an incompatible schema';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_namespace AS namespace_row
      ON namespace_row.oid = procedure_row.pronamespace
    WHERE namespace_row.nspname = 'public'
      AND procedure_row.proname = 'save_bilty_with_items_v2'
      AND procedure_row.prorettype = 'uuid'::pg_catalog.regtype
  ) THEN
    RAISE EXCEPTION 'BILTY_DETAIN_CHARGES: existing Bilty save RPC is missing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_namespace AS namespace_row
      ON namespace_row.oid = procedure_row.pronamespace
    WHERE namespace_row.nspname = 'public'
      AND procedure_row.proname = 'save_bilty_detain_charges'
  ) THEN
    RAISE EXCEPTION 'BILTY_DETAIN_CHARGES: save_bilty_detain_charges name is already in use';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid = 'public.bookings'::pg_catalog.regclass
      AND attribute_row.attname = 'detain_charges'
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
      AND (
        attribute_row.atttypid <> 'numeric'::pg_catalog.regtype
        OR attribute_row.attnotnull IS DISTINCT FROM true
      )
  ) THEN
    RAISE EXCEPTION 'BILTY_DETAIN_CHARGES: existing detain_charges column has an incompatible type or nullability';
  END IF;
END;
$preflight$;

ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS detain_charges numeric NOT NULL DEFAULT 0;

DO $constraint$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = 'public.bookings'::pg_catalog.regclass
      AND constraint_row.conname = 'bookings_detain_charges_nonnegative_check'
  ) THEN
    ALTER TABLE public.bookings
      ADD CONSTRAINT bookings_detain_charges_nonnegative_check
      CHECK (
        detain_charges >= 0
        AND detain_charges::text NOT IN ('NaN', 'Infinity', '-Infinity')
      );
  END IF;
END;
$constraint$;

CREATE FUNCTION public.save_bilty_detain_charges(
  p_adda_id uuid,
  p_bilty_id uuid,
  p_detain_charges numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  caller_role text;
  caller_adda_id uuid;
  caller_active boolean;
  resolved_detain_charges numeric := coalesce(p_detain_charges, 0);
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'AUTHENTICATION_REQUIRED';
  END IF;

  SELECT profile.role, profile.adda_id, profile.is_active
  INTO caller_role, caller_adda_id, caller_active
  FROM public.profiles AS profile
  WHERE profile.id = auth.uid();

  IF caller_active IS DISTINCT FROM true
     OR caller_role IS NULL
     OR caller_role NOT IN ('super_admin', 'adda_admin', 'operator') THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'BILTY_ACCESS_DENIED';
  END IF;

  IF p_adda_id IS NULL OR p_bilty_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.addas AS adda WHERE adda.id = p_adda_id) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'BILTY_ADDA_AND_ID_REQUIRED';
  END IF;

  IF caller_role <> 'super_admin' AND caller_adda_id IS DISTINCT FROM p_adda_id THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'BILTY_ADDA_ACCESS_DENIED';
  END IF;

  IF resolved_detain_charges < 0
     OR resolved_detain_charges::text IN ('NaN', 'Infinity', '-Infinity') THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'DETAIN_CHARGES_MUST_BE_ZERO_OR_GREATER';
  END IF;

  UPDATE public.bookings AS booking
  SET detain_charges = resolved_detain_charges
  WHERE booking.id = p_bilty_id
    AND booking.adda_id = p_adda_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'BILTY_NOT_FOUND_IN_ADDA';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.save_bilty_detain_charges(uuid, uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_bilty_detain_charges(uuid, uuid, numeric) TO authenticated;

DO $postcondition$
DECLARE
  function_oid oid := pg_catalog.to_regprocedure(
    'public.save_bilty_detain_charges(uuid,uuid,numeric)'
  );
  function_config text[];
  function_acl pg_catalog.aclitem[];
  function_owner oid;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute_row
    JOIN pg_catalog.pg_attrdef AS default_row
      ON default_row.adrelid = attribute_row.attrelid
     AND default_row.adnum = attribute_row.attnum
    WHERE attribute_row.attrelid = 'public.bookings'::pg_catalog.regclass
      AND attribute_row.attname = 'detain_charges'
      AND attribute_row.atttypid = 'numeric'::pg_catalog.regtype
      AND attribute_row.attnotnull
      AND pg_catalog.pg_get_expr(default_row.adbin, default_row.adrelid) IN ('0', '0::numeric')
  ) THEN
    RAISE EXCEPTION 'BILTY_DETAIN_CHARGES_COLUMN_POSTCONDITION_FAILED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = 'public.bookings'::pg_catalog.regclass
      AND constraint_row.conname = 'bookings_detain_charges_nonnegative_check'
      AND constraint_row.convalidated
  ) THEN
    RAISE EXCEPTION 'BILTY_DETAIN_CHARGES_CHECK_POSTCONDITION_FAILED';
  END IF;

  IF function_oid IS NULL THEN
    RAISE EXCEPTION 'BILTY_DETAIN_CHARGES_RPC_POSTCONDITION_FAILED';
  END IF;

  SELECT procedure_row.proconfig,
         procedure_row.proacl,
         procedure_row.proowner
  INTO function_config, function_acl, function_owner
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = function_oid;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = function_oid
      AND procedure_row.prosecdef
      AND procedure_row.provolatile = 'v'
  ) THEN
    RAISE EXCEPTION 'BILTY_DETAIN_CHARGES_RPC_SECURITY_POSTCONDITION_FAILED';
  END IF;

  IF NOT coalesce(function_config @> ARRAY['search_path=""'], false)
     AND NOT coalesce(function_config @> ARRAY['search_path='], false) THEN
    RAISE EXCEPTION 'BILTY_DETAIN_CHARGES_RPC_SEARCH_PATH_POSTCONDITION_FAILED';
  END IF;

  IF EXISTS (
       SELECT 1 FROM pg_catalog.aclexplode(
         coalesce(function_acl, pg_catalog.acldefault('f', function_owner))
       ) AS acl_row
       WHERE acl_row.grantee = 0 AND acl_row.privilege_type = 'EXECUTE'
     )
     OR pg_catalog.has_function_privilege('anon', function_oid, 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated', function_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'BILTY_DETAIN_CHARGES_RPC_ACL_POSTCONDITION_FAILED';
  END IF;
END;
$postcondition$;

COMMIT;
