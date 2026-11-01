-- Read-only discovery of the live authorization contract used by Broker RPCs.
-- Returns only routine/catalog metadata and definitions; no application rows.
WITH target_functions(function_name, identity_arguments, signature) AS (
  VALUES
    (
      'ut_resolve_broker_transaction_adda',
      'p_adda_id uuid',
      'public.ut_resolve_broker_transaction_adda(uuid)'
    ),
    (
      'current_user_adda_id',
      '',
      'public.current_user_adda_id()'
    ),
    (
      'current_user_role',
      '',
      'public.current_user_role()'
    ),
    (
      'is_super_admin',
      '',
      'public.is_super_admin()'
    ),
    (
      'save_manual_cashbook_entry',
      'p_entry_date date, p_entry_type text, p_person_type text, p_person_name text, p_vehicle_id uuid, p_driver_id uuid, p_loading_id bigint, p_payment_method text, p_amount numeric, p_description text, p_adda_id uuid, p_id bigint',
      'public.save_manual_cashbook_entry(date,text,text,text,uuid,uuid,bigint,text,numeric,text,uuid,bigint)'
    ),
    (
      'save_manual_cashbook_entry_impl',
      'p_entry_date date, p_entry_type text, p_person_type text, p_person_name text, p_vehicle_id uuid, p_driver_id uuid, p_loading_id bigint, p_payment_method text, p_amount numeric, p_description text, p_adda_id uuid, p_id bigint',
      'public.save_manual_cashbook_entry_impl(date,text,text,text,uuid,uuid,bigint,text,numeric,text,uuid,bigint)'
    ),
    (
      'delete_manual_cashbook_entry',
      'p_id bigint, p_adda_id uuid',
      'public.delete_manual_cashbook_entry(bigint,uuid)'
    ),
    (
      'delete_manual_cashbook_entry_impl',
      'p_id bigint, p_adda_id uuid',
      'public.delete_manual_cashbook_entry_impl(bigint,uuid)'
    )
), routine_catalog AS (
  SELECT
    target.function_name,
    target.identity_arguments AS expected_identity_arguments,
    target.signature,
    proc.oid,
    proc.proname,
    pg_catalog.pg_get_function_identity_arguments(proc.oid) AS live_identity_arguments,
    pg_catalog.pg_get_function_result(proc.oid) AS return_type,
    owner_role.rolname AS owner_name,
    language_row.lanname AS language_name,
    proc.prosecdef AS security_definer,
    proc.proconfig AS function_config,
    CASE WHEN proc.oid IS NOT NULL
      THEN pg_catalog.has_function_privilege('anon', proc.oid, 'EXECUTE')
    END AS anon_execute,
    CASE WHEN proc.oid IS NOT NULL
      THEN pg_catalog.has_function_privilege('authenticated', proc.oid, 'EXECUTE')
    END AS authenticated_execute,
    CASE WHEN proc.oid IS NOT NULL
      THEN pg_catalog.has_function_privilege('service_role', proc.oid, 'EXECUTE')
    END AS service_role_execute,
    CASE WHEN proc.oid IS NOT NULL THEN EXISTS (
      SELECT 1
      FROM pg_catalog.aclexplode(
        COALESCE(proc.proacl, pg_catalog.acldefault('f', proc.proowner))
      ) AS acl_row
      WHERE acl_row.grantee = 0
        AND acl_row.privilege_type = 'EXECUTE'
    ) END AS public_execute,
    CASE WHEN proc.oid IS NOT NULL
      THEN pg_catalog.pg_get_functiondef(proc.oid)
    END AS function_definition
  FROM target_functions AS target
  LEFT JOIN pg_catalog.pg_proc AS proc
    ON proc.oid = pg_catalog.to_regprocedure(target.signature)
  LEFT JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = proc.proowner
  LEFT JOIN pg_catalog.pg_language AS language_row
    ON language_row.oid = proc.prolang
)
SELECT
  function_name,
  signature,
  oid IS NOT NULL AS function_exists,
  expected_identity_arguments,
  live_identity_arguments,
  return_type,
  owner_name,
  language_name,
  security_definer,
  function_config,
  anon_execute,
  authenticated_execute,
  public_execute,
  service_role_execute,
  function_definition
FROM routine_catalog
ORDER BY function_name;
