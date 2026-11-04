BEGIN;

DO $precondition$
BEGIN
  IF pg_catalog.to_regclass('public.addas') IS NULL
     OR pg_catalog.to_regclass('public.profiles') IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'ADDAS_PROFILES_PRIVILEGE_CLEANUP_REQUIRED_TABLE_MISSING';
  END IF;

  IF pg_catalog.to_regrole('authenticated') IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'ADDAS_PROFILES_PRIVILEGE_CLEANUP_AUTHENTICATED_ROLE_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES ('addas'::text), ('profiles'::text)) AS target(table_name)
    LEFT JOIN pg_catalog.pg_class AS relation_row
      ON relation_row.relnamespace = pg_catalog.to_regnamespace('public')
     AND relation_row.relname = target.table_name
     AND relation_row.relkind IN ('r', 'p')
    WHERE relation_row.oid IS NULL
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'ADDAS_PROFILES_PRIVILEGE_CLEANUP_REQUIRED_RELATION_NOT_A_TABLE';
  END IF;
END;
$precondition$;

-- Remove only the four unnecessary table-level privileges from authenticated.
-- CRUD, policies, service_role, PUBLIC, and other roles are untouched.
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
ON TABLE public.addas, public.profiles
FROM authenticated;

-- Also clear any direct column-level REFERENCES grants for authenticated on
-- these same tables; no other column privilege or grantee is changed.
DO $column_references$
DECLARE
  v_column record;
  v_authenticated_oid oid;
BEGIN
  SELECT role_row.oid
  INTO v_authenticated_oid
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname = 'authenticated';

  FOR v_column IN
    SELECT
      namespace_row.nspname AS schema_name,
      relation_row.relname AS table_name,
      attribute_row.attname AS column_name
    FROM pg_catalog.pg_class AS relation_row
    JOIN pg_catalog.pg_namespace AS namespace_row
      ON namespace_row.oid = relation_row.relnamespace
    JOIN pg_catalog.pg_attribute AS attribute_row
      ON attribute_row.attrelid = relation_row.oid
    CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_row.attacl) AS acl_row
    WHERE namespace_row.nspname = 'public'
      AND relation_row.relname IN ('addas', 'profiles')
      AND relation_row.relkind IN ('r', 'p')
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
      AND attribute_row.attacl IS NOT NULL
      AND acl_row.grantee = v_authenticated_oid
      AND acl_row.privilege_type = 'REFERENCES'
  LOOP
    EXECUTE pg_catalog.format(
      'REVOKE REFERENCES (%I) ON TABLE %I.%I FROM authenticated',
      v_column.column_name,
      v_column.schema_name,
      v_column.table_name
    );
  END LOOP;
END;
$column_references$;

-- Fail transactionally if a direct authenticated grant remains.
DO $postcondition$
DECLARE
  v_authenticated_oid oid;
BEGIN
  SELECT role_row.oid
  INTO v_authenticated_oid
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname = 'authenticated';

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS relation_row
    JOIN pg_catalog.pg_namespace AS namespace_row
      ON namespace_row.oid = relation_row.relnamespace
    CROSS JOIN LATERAL pg_catalog.aclexplode(
      COALESCE(relation_row.relacl, pg_catalog.acldefault('r', relation_row.relowner))
    ) AS acl_row
    WHERE namespace_row.nspname = 'public'
      AND relation_row.relname IN ('addas', 'profiles')
      AND relation_row.relkind IN ('r', 'p')
      AND acl_row.grantee = v_authenticated_oid
      AND acl_row.privilege_type IN ('TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN')
  ) OR EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS relation_row
    JOIN pg_catalog.pg_namespace AS namespace_row
      ON namespace_row.oid = relation_row.relnamespace
    JOIN pg_catalog.pg_attribute AS attribute_row
      ON attribute_row.attrelid = relation_row.oid
    CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_row.attacl) AS acl_row
    WHERE namespace_row.nspname = 'public'
      AND relation_row.relname IN ('addas', 'profiles')
      AND relation_row.relkind IN ('r', 'p')
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
      AND attribute_row.attacl IS NOT NULL
      AND acl_row.grantee = v_authenticated_oid
      AND acl_row.privilege_type = 'REFERENCES'
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'ADDAS_PROFILES_PRIVILEGE_CLEANUP_DIRECT_GRANT_POSTCONDITION_FAILED';
  END IF;
END;
$postcondition$;

COMMIT;
