BEGIN;

DO $bilty_payments_acl_preconditions$
DECLARE
  payments_oid oid := pg_catalog.to_regclass('public.bilty_payments');
  authenticated_oid oid;
  service_role_oid oid;
  relation_owner text;
  rls_enabled boolean;
  force_rls boolean;
  policy_total bigint;
  server_version integer := pg_catalog.current_setting('server_version_num')::integer;
BEGIN
  IF payments_oid IS NULL THEN
    RAISE EXCEPTION 'BILTY_PAYMENTS_ACL_TABLE_MISSING';
  END IF;

  SELECT role_row.oid INTO authenticated_oid
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname = 'authenticated';

  SELECT role_row.oid INTO service_role_oid
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname = 'service_role';

  IF authenticated_oid IS NULL OR service_role_oid IS NULL THEN
    RAISE EXCEPTION 'BILTY_PAYMENTS_ACL_REQUIRED_ROLE_MISSING';
  END IF;

  SELECT relation_row.relowner::pg_catalog.regrole::text,
         relation_row.relrowsecurity,
         relation_row.relforcerowsecurity
  INTO relation_owner, rls_enabled, force_rls
  FROM pg_catalog.pg_class AS relation_row
  WHERE relation_row.oid = payments_oid;

  SELECT pg_catalog.count(*)
  INTO policy_total
  FROM pg_catalog.pg_policy AS policy_row
  WHERE policy_row.polrelid = payments_oid;

  IF relation_owner IS DISTINCT FROM 'postgres'
     OR rls_enabled IS DISTINCT FROM true
     OR force_rls IS DISTINCT FROM false
     OR policy_total <> 4 THEN
    RAISE EXCEPTION 'BILTY_PAYMENTS_ACL_SECURITY_BASELINE_DRIFT';
  END IF;

  IF NOT pg_catalog.has_table_privilege(authenticated_oid, payments_oid, 'SELECT')
     OR NOT pg_catalog.has_table_privilege(authenticated_oid, payments_oid, 'INSERT')
     OR NOT pg_catalog.has_table_privilege(authenticated_oid, payments_oid, 'UPDATE')
     OR NOT pg_catalog.has_table_privilege(authenticated_oid, payments_oid, 'DELETE') THEN
    RAISE EXCEPTION 'BILTY_PAYMENTS_ACL_AUTHENTICATED_CRUD_BASELINE_DRIFT';
  END IF;

  IF NOT pg_catalog.has_table_privilege(service_role_oid, payments_oid, 'SELECT')
     OR NOT pg_catalog.has_table_privilege(service_role_oid, payments_oid, 'INSERT')
     OR NOT pg_catalog.has_table_privilege(service_role_oid, payments_oid, 'UPDATE')
     OR NOT pg_catalog.has_table_privilege(service_role_oid, payments_oid, 'DELETE')
     OR NOT pg_catalog.has_table_privilege(service_role_oid, payments_oid, 'TRUNCATE')
     OR NOT pg_catalog.has_table_privilege(service_role_oid, payments_oid, 'REFERENCES')
     OR NOT pg_catalog.has_table_privilege(service_role_oid, payments_oid, 'TRIGGER') THEN
    RAISE EXCEPTION 'BILTY_PAYMENTS_ACL_SERVICE_ROLE_BASELINE_DRIFT';
  END IF;

  IF server_version >= 170000 THEN
    IF NOT pg_catalog.has_table_privilege(service_role_oid, payments_oid, 'MAINTAIN') THEN
      RAISE EXCEPTION 'BILTY_PAYMENTS_ACL_SERVICE_ROLE_MAINTAIN_BASELINE_DRIFT';
    END IF;
  END IF;

  IF pg_catalog.has_table_privilege('anon', payments_oid, 'SELECT')
     OR pg_catalog.has_table_privilege('anon', payments_oid, 'INSERT')
     OR pg_catalog.has_table_privilege('anon', payments_oid, 'UPDATE')
     OR pg_catalog.has_table_privilege('anon', payments_oid, 'DELETE') THEN
    RAISE EXCEPTION 'BILTY_PAYMENTS_ACL_ANON_BASELINE_DRIFT';
  END IF;
END
$bilty_payments_acl_preconditions$;

REVOKE TRUNCATE, REFERENCES, TRIGGER
  ON TABLE public.bilty_payments
  FROM authenticated;

DO $bilty_payments_acl_maintain_revoke$
BEGIN
  IF pg_catalog.current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE 'REVOKE MAINTAIN ON TABLE public.bilty_payments FROM authenticated';
  END IF;
END
$bilty_payments_acl_maintain_revoke$;

DO $bilty_payments_acl_postconditions$
DECLARE
  payments_oid oid := pg_catalog.to_regclass('public.bilty_payments');
  authenticated_oid oid;
  service_role_oid oid;
  server_version integer := pg_catalog.current_setting('server_version_num')::integer;
  policy_total bigint;
BEGIN
  SELECT role_row.oid INTO authenticated_oid
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname = 'authenticated';

  SELECT role_row.oid INTO service_role_oid
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname = 'service_role';

  IF payments_oid IS NULL OR authenticated_oid IS NULL OR service_role_oid IS NULL THEN
    RAISE EXCEPTION 'BILTY_PAYMENTS_ACL_POSTCONDITION_TARGET_MISSING';
  END IF;

  IF pg_catalog.has_table_privilege(authenticated_oid, payments_oid, 'TRUNCATE')
     OR pg_catalog.has_table_privilege(authenticated_oid, payments_oid, 'REFERENCES')
     OR pg_catalog.has_table_privilege(authenticated_oid, payments_oid, 'TRIGGER') THEN
    RAISE EXCEPTION 'BILTY_PAYMENTS_ACL_AUTHENTICATED_EXTRA_PRIVILEGE_REMAINS';
  END IF;

  IF server_version >= 170000 THEN
    IF pg_catalog.has_table_privilege(authenticated_oid, payments_oid, 'MAINTAIN') THEN
      RAISE EXCEPTION 'BILTY_PAYMENTS_ACL_AUTHENTICATED_MAINTAIN_REMAINS';
    END IF;
  END IF;

  IF NOT pg_catalog.has_table_privilege(authenticated_oid, payments_oid, 'SELECT')
     OR NOT pg_catalog.has_table_privilege(authenticated_oid, payments_oid, 'INSERT')
     OR NOT pg_catalog.has_table_privilege(authenticated_oid, payments_oid, 'UPDATE')
     OR NOT pg_catalog.has_table_privilege(authenticated_oid, payments_oid, 'DELETE') THEN
    RAISE EXCEPTION 'BILTY_PAYMENTS_ACL_AUTHENTICATED_CRUD_CHANGED';
  END IF;

  IF NOT pg_catalog.has_table_privilege(service_role_oid, payments_oid, 'SELECT')
     OR NOT pg_catalog.has_table_privilege(service_role_oid, payments_oid, 'INSERT')
     OR NOT pg_catalog.has_table_privilege(service_role_oid, payments_oid, 'UPDATE')
     OR NOT pg_catalog.has_table_privilege(service_role_oid, payments_oid, 'DELETE')
     OR NOT pg_catalog.has_table_privilege(service_role_oid, payments_oid, 'TRUNCATE')
     OR NOT pg_catalog.has_table_privilege(service_role_oid, payments_oid, 'REFERENCES')
     OR NOT pg_catalog.has_table_privilege(service_role_oid, payments_oid, 'TRIGGER') THEN
    RAISE EXCEPTION 'BILTY_PAYMENTS_ACL_SERVICE_ROLE_CHANGED';
  END IF;

  IF server_version >= 170000 THEN
    IF NOT pg_catalog.has_table_privilege(service_role_oid, payments_oid, 'MAINTAIN') THEN
      RAISE EXCEPTION 'BILTY_PAYMENTS_ACL_SERVICE_ROLE_MAINTAIN_CHANGED';
    END IF;
  END IF;

  IF pg_catalog.has_table_privilege('anon', payments_oid, 'SELECT')
     OR pg_catalog.has_table_privilege('anon', payments_oid, 'INSERT')
     OR pg_catalog.has_table_privilege('anon', payments_oid, 'UPDATE')
     OR pg_catalog.has_table_privilege('anon', payments_oid, 'DELETE') THEN
    RAISE EXCEPTION 'BILTY_PAYMENTS_ACL_ANON_ACCESS_CHANGED';
  END IF;

  SELECT pg_catalog.count(*)
  INTO policy_total
  FROM pg_catalog.pg_policy AS policy_row
  WHERE policy_row.polrelid = payments_oid;

  IF NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_class AS relation_row
       WHERE relation_row.oid = payments_oid
         AND relation_row.relrowsecurity
         AND NOT relation_row.relforcerowsecurity
     )
     OR policy_total <> 4 THEN
    RAISE EXCEPTION 'BILTY_PAYMENTS_ACL_RLS_OR_POLICY_SET_CHANGED';
  END IF;
END
$bilty_payments_acl_postconditions$;

COMMIT;
