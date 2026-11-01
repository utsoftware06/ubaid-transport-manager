BEGIN;

-- PostgreSQL places TEMP tables in the session's pg_temp schema. Keep this
-- transaction snapshot relation alive from the start through final checks.
CREATE TEMP TABLE phase6a_bookings_migration_snapshot (
  booking_rows jsonb NOT NULL,
  save_bilty_rpc jsonb NOT NULL,
  service_role_acl jsonb NOT NULL,
  service_role_effective jsonb NOT NULL
) ON COMMIT PRESERVE ROWS;

DO $phase6a_preconditions$
DECLARE
  bookings_oid oid := pg_catalog.to_regclass('public.bookings');
  addas_oid oid := pg_catalog.to_regclass('public.addas');
  expected_policy_count bigint;
  dual_other_adda_count bigint;
  bad_booking_count bigint;
  save_rpc_count bigint;
  save_rpc_contract record;
  normalized_save_rpc_body text;
  scoped_booking_update_ok boolean;
  other_adda_post_call_ok boolean;
BEGIN
  IF bookings_oid IS NULL OR addas_oid IS NULL THEN
    RAISE EXCEPTION 'SECURITY_PHASE6A_BOOKINGS_TARGET_OR_ADDA_TABLE_MISSING';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid = bookings_oid
      AND attribute_row.attname = 'adda_id'
      AND attribute_row.atttypid = pg_catalog.to_regtype('uuid')
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6A_BOOKINGS_ADDA_ID_SCHEMA_DRIFT';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS relation_row
    WHERE relation_row.oid = bookings_oid
      AND relation_row.relrowsecurity
      AND NOT relation_row.relforcerowsecurity
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6A_BOOKINGS_RLS_BASELINE_DRIFT';
  END IF;

  IF pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NULL
     OR pg_catalog.to_regprocedure('public.is_super_admin()') IS NULL
     OR pg_catalog.to_regprocedure('public.current_user_role()') IS NULL THEN
    RAISE EXCEPTION 'SECURITY_PHASE6A_AUTH_HELPERS_MISSING';
  END IF;

  IF NOT pg_catalog.has_function_privilege('authenticated', 'public.current_user_adda_id()', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated', 'public.is_super_admin()', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated', 'public.current_user_role()', 'EXECUTE') THEN
    RAISE EXCEPTION 'SECURITY_PHASE6A_AUTH_HELPER_EXECUTE_MISSING';
  END IF;

  SELECT pg_catalog.count(*) FILTER (WHERE booking_row.adda_id IS NULL
           OR NOT EXISTS (
             SELECT 1 FROM public.addas AS adda_row
             WHERE adda_row.id = booking_row.adda_id
           ))::bigint
    INTO bad_booking_count
  FROM public.bookings AS booking_row;

  IF bad_booking_count <> 0 THEN
    RAISE EXCEPTION 'SECURITY_PHASE6A_BOOKINGS_UNRESOLVED_TENANT_ROWS: invalid=%', bad_booking_count;
  END IF;

  SELECT pg_catalog.count(*)::bigint
    INTO dual_other_adda_count
  FROM public.bookings AS booking_row
  WHERE booking_row.loading_source_other_adda_id IS NOT NULL
    AND booking_row.freight_receivable_other_adda_id IS NOT NULL;

  IF dual_other_adda_count < 1 THEN
    RAISE EXCEPTION 'SECURITY_PHASE6A_OTHER_ADDA_BOOKING_BASELINE_DRIFT: rows=%', dual_other_adda_count;
  END IF;

  SELECT pg_catalog.count(*)::bigint
    INTO expected_policy_count
  FROM pg_catalog.pg_policy AS policy_row
  WHERE policy_row.polrelid = bookings_oid;

  IF expected_policy_count <> 3
     OR NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_policy AS policy_row
       WHERE policy_row.polrelid = bookings_oid
         AND policy_row.polname = 'Allow select on bookings'
         AND policy_row.polcmd = 'r'
         AND policy_row.polpermissive
         AND policy_row.polroles = ARRAY[0::oid]
         AND pg_catalog.regexp_replace(
           pg_catalog.lower(COALESCE(pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid), '')),
           '[[:space:]()]', '', 'g'
         ) = 'true'
         AND policy_row.polwithcheck IS NULL
     )
     OR NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_policy AS policy_row
       WHERE policy_row.polrelid = bookings_oid
         AND policy_row.polname = 'Allow insert on bookings'
         AND policy_row.polcmd = 'a'
         AND policy_row.polpermissive
         AND policy_row.polroles = ARRAY[0::oid]
         AND policy_row.polqual IS NULL
         AND pg_catalog.regexp_replace(
           pg_catalog.lower(COALESCE(pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid), '')),
           '[[:space:]()]', '', 'g'
         ) = 'true'
     )
     OR NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_policy AS policy_row
       WHERE policy_row.polrelid = bookings_oid
         AND policy_row.polname = 'Allow update on bookings'
         AND policy_row.polcmd = 'w'
         AND policy_row.polpermissive
         AND policy_row.polroles = ARRAY[0::oid]
         AND pg_catalog.regexp_replace(
           pg_catalog.lower(COALESCE(pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid), '')),
           '[[:space:]()]', '', 'g'
         ) = 'true'
         AND pg_catalog.regexp_replace(
           pg_catalog.lower(COALESCE(pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid), '')),
           '[[:space:]()]', '', 'g'
         ) = 'true'
     ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6A_UNEXPECTED_BOOKINGS_POLICY_SET';
  END IF;

  SELECT pg_catalog.count(*)::bigint
    INTO save_rpc_count
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.proname = 'save_bilty_with_items_v2';

  IF save_rpc_count <> 1 THEN
    RAISE EXCEPTION 'SECURITY_PHASE6A_BILTY_RPC_CONTRACT_DRIFT';
  END IF;

  SELECT procedure_row.oid,
         pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
         procedure_row.prorettype,
         pg_catalog.format_type(procedure_row.prorettype, NULL) AS return_type,
         procedure_row.proargtypes::text AS identity_type_oids,
         procedure_row.proallargtypes::text AS all_type_oids,
         procedure_row.proargmodes::text AS argument_modes,
         procedure_row.proargnames::text AS argument_names,
         procedure_row.pronargdefaults AS default_count,
         pg_catalog.pg_get_expr(procedure_row.proargdefaults, 0) AS defaults_expression,
         pg_catalog.pg_get_userbyid(procedure_row.proowner) AS owner_name,
         procedure_row.prosecdef,
         procedure_row.provolatile,
         procedure_row.proconfig,
         pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE') AS anon_execute,
         pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE') AS authenticated_execute,
         pg_catalog.has_function_privilege('service_role', procedure_row.oid, 'EXECUTE') AS service_role_execute,
         EXISTS (
           SELECT 1
           FROM pg_catalog.aclexplode(COALESCE(
             procedure_row.proacl,
             pg_catalog.acldefault('f', procedure_row.proowner)
           )) AS acl_row
           WHERE acl_row.grantee = 0 AND acl_row.privilege_type = 'EXECUTE'
         ) AS public_execute,
         procedure_row.prosrc AS body_source
    INTO save_rpc_contract
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.proname = 'save_bilty_with_items_v2';

  normalized_save_rpc_body := pg_catalog.replace(
    pg_catalog.regexp_replace(pg_catalog.lower(save_rpc_contract.body_source), '[[:space:]]', '', 'g'),
    '"', ''
  );
  scoped_booking_update_ok := normalized_save_rpc_body ~* 'update(public[.])?bookings[^;]*where[(]*(([[:alnum:]_]+[.])*id=[[:alnum:]_]*(saved|booking|bilty)[[:alnum:]_]*id(::[[:alnum:]_.]+)?[)]*and[(]*([[:alnum:]_]+[.])*adda_id=p_adda_id[)]*|([[:alnum:]_]+[.])*adda_id=p_adda_id[)]*and[(]*([[:alnum:]_]+[.])*id=[[:alnum:]_]*(saved|booking|bilty)[[:alnum:]_]*id(::[[:alnum:]_.]+)?[)]*)';
  other_adda_post_call_ok := normalized_save_rpc_body ~* '(perform|select|call|return|:=)[(]*(public[.])?[[:alnum:]_]*(other_adda[[:alnum:]_]*(obligation|transaction)|(obligation|transaction)[[:alnum:]_]*other_adda)[[:alnum:]_]*[(]';

  IF save_rpc_contract.prorettype <> pg_catalog.to_regtype('uuid')
     OR save_rpc_contract.owner_name <> 'postgres'
     OR save_rpc_contract.prosecdef
     OR save_rpc_contract.provolatile <> 'v'
     OR COALESCE(pg_catalog.array_length(save_rpc_contract.proconfig, 1), 0) <> 1
     OR pg_catalog.replace(
          pg_catalog.regexp_replace(pg_catalog.lower(save_rpc_contract.proconfig[1]), '[[:space:]]', '', 'g'),
          '"', ''
        ) <> 'search_path='
     OR save_rpc_contract.anon_execute
     OR NOT save_rpc_contract.authenticated_execute
     OR NOT save_rpc_contract.service_role_execute
     OR save_rpc_contract.public_execute
     OR save_rpc_contract.identity_arguments IS NULL
     OR save_rpc_contract.body_source !~* 'loading_source'
     OR save_rpc_contract.body_source !~* 'freight_receivable_from'
     OR save_rpc_contract.body_source !~* 'loading_source_other_adda_id'
     OR save_rpc_contract.body_source !~* 'freight_receivable_other_adda_id'
     OR save_rpc_contract.body_source !~* 'p_adda_id'
     OR save_rpc_contract.body_source !~* 'save_bilty_with_items[[:space:]]*\('
     OR save_rpc_contract.body_source !~* 'update[[:space:]]+(public[.])?bookings'
     OR NOT scoped_booking_update_ok
     OR NOT other_adda_post_call_ok THEN
    RAISE EXCEPTION 'SECURITY_PHASE6A_BILTY_RPC_CONTRACT_DRIFT';
  END IF;
END;
$phase6a_preconditions$;

INSERT INTO pg_temp.phase6a_bookings_migration_snapshot (
  booking_rows,
  save_bilty_rpc,
  service_role_acl,
  service_role_effective
)
SELECT
  (
    SELECT COALESCE(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object('id', booking_row.id, 'row', pg_catalog.to_jsonb(booking_row))
        ORDER BY booking_row.id
      ), '[]'::jsonb
    )
    FROM public.bookings AS booking_row
  ) AS booking_rows,
  (
    SELECT COALESCE(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'oid', procedure_row.oid,
          'schema', namespace_row.nspname,
          'name', procedure_row.proname,
          'identity_arguments', pg_catalog.pg_get_function_identity_arguments(procedure_row.oid),
          'identity_type_oids', procedure_row.proargtypes::text,
          'all_type_oids', procedure_row.proallargtypes::text,
          'argument_modes', procedure_row.proargmodes::text,
          'argument_names', procedure_row.proargnames::text,
          'default_count', procedure_row.pronargdefaults,
          'defaults_expression', pg_catalog.pg_get_expr(procedure_row.proargdefaults, 0),
          'return_type_oid', procedure_row.prorettype,
          'return_type', pg_catalog.format_type(procedure_row.prorettype, NULL),
          'owner', procedure_row.proowner,
          'owner_name', pg_catalog.pg_get_userbyid(procedure_row.proowner),
          'security_definer', procedure_row.prosecdef,
          'volatility', procedure_row.provolatile::text,
          'language', language_row.lanname,
          'kind', procedure_row.prokind::text,
          'normalized_config', COALESCE(ARRAY(
            SELECT pg_catalog.replace(
                     pg_catalog.regexp_replace(pg_catalog.lower(setting_row.setting), '[[:space:]]', '', 'g'),
                     '"', ''
                   )
            FROM pg_catalog.unnest(COALESCE(procedure_row.proconfig, ARRAY[]::text[])) AS setting_row(setting)
            ORDER BY 1
          ), ARRAY[]::text[]),
          'anon_execute', pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE'),
          'authenticated_execute', pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE'),
          'service_role_execute', pg_catalog.has_function_privilege('service_role', procedure_row.oid, 'EXECUTE'),
          'public_execute', EXISTS (
            SELECT 1
            FROM pg_catalog.aclexplode(COALESCE(
              procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner)
            )) AS acl_row
            WHERE acl_row.grantee = 0 AND acl_row.privilege_type = 'EXECUTE'
          ),
          'body_fingerprint', pg_catalog.md5(
            pg_catalog.replace(pg_catalog.replace(procedure_row.prosrc, E'\r\n', E'\n'), E'\r', E'\n')
          )
        ) ORDER BY procedure_row.oid
      ), '[]'::jsonb
    )
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_namespace AS namespace_row
      ON namespace_row.oid = procedure_row.pronamespace
    JOIN pg_catalog.pg_language AS language_row
      ON language_row.oid = procedure_row.prolang
    WHERE namespace_row.nspname = 'public'
      AND procedure_row.proname = 'save_bilty_with_items_v2'
  ) AS save_bilty_rpc,
  (
    SELECT COALESCE(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'grantor', acl_row.grantor,
          'privilege', acl_row.privilege_type,
          'grantable', acl_row.is_grantable
        ) ORDER BY acl_row.grantor, acl_row.privilege_type, acl_row.is_grantable
      ), '[]'::jsonb
    )
    FROM pg_catalog.pg_class AS relation_row
    CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(
      relation_row.relacl,
      pg_catalog.acldefault('r', relation_row.relowner)
    )) AS acl_row
    WHERE relation_row.oid = pg_catalog.to_regclass('public.bookings')
      AND acl_row.grantee = (SELECT role_row.oid FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'service_role')
  ) AS service_role_acl,
  pg_catalog.jsonb_build_object(
    'select', pg_catalog.has_table_privilege('service_role', 'public.bookings', 'SELECT'),
    'insert', pg_catalog.has_table_privilege('service_role', 'public.bookings', 'INSERT'),
    'update', pg_catalog.has_table_privilege('service_role', 'public.bookings', 'UPDATE'),
    'delete', pg_catalog.has_table_privilege('service_role', 'public.bookings', 'DELETE'),
    'truncate', pg_catalog.has_table_privilege('service_role', 'public.bookings', 'TRUNCATE'),
    'references', pg_catalog.has_table_privilege('service_role', 'public.bookings', 'REFERENCES'),
    'trigger', pg_catalog.has_table_privilege('service_role', 'public.bookings', 'TRIGGER')
  ) AS service_role_effective;

DROP POLICY "Allow select on bookings" ON public.bookings;
DROP POLICY "Allow insert on bookings" ON public.bookings;
DROP POLICY "Allow update on bookings" ON public.bookings;

DO $phase6a_column_grant_cleanup$
DECLARE
  column_row record;
BEGIN
  FOR column_row IN
    SELECT attribute_row.attname
    FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid = pg_catalog.to_regclass('public.bookings')
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
  LOOP
    EXECUTE pg_catalog.format(
      'REVOKE ALL PRIVILEGES (%I) ON TABLE public.bookings FROM PUBLIC, anon, authenticated',
      column_row.attname
    );
  END LOOP;
END;
$phase6a_column_grant_cleanup$;

REVOKE ALL PRIVILEGES ON TABLE public.bookings FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.bookings TO authenticated;

CREATE POLICY bookings_tenant_select
  ON public.bookings
  FOR SELECT
  TO authenticated
  USING (
    bookings.adda_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.addas AS adda_row
      WHERE adda_row.id = bookings.adda_id
    )
    AND (
      (SELECT public.is_super_admin())
      OR bookings.adda_id = (SELECT public.current_user_adda_id())
    )
  );

CREATE POLICY bookings_tenant_insert
  ON public.bookings
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bookings.adda_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.addas AS adda_row
      WHERE adda_row.id = bookings.adda_id
    )
    AND (
      (SELECT public.is_super_admin())
      OR bookings.adda_id = (SELECT public.current_user_adda_id())
    )
  );

CREATE POLICY bookings_tenant_update
  ON public.bookings
  FOR UPDATE
  TO authenticated
  USING (
    bookings.adda_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.addas AS adda_row
      WHERE adda_row.id = bookings.adda_id
    )
    AND (
      (SELECT public.is_super_admin())
      OR bookings.adda_id = (SELECT public.current_user_adda_id())
    )
  )
  WITH CHECK (
    bookings.adda_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.addas AS adda_row
      WHERE adda_row.id = bookings.adda_id
    )
    AND (
      (SELECT public.is_super_admin())
      OR bookings.adda_id = (SELECT public.current_user_adda_id())
    )
  );

DO $phase6a_postconditions$
DECLARE
  bookings_oid oid := pg_catalog.to_regclass('public.bookings');
  authenticated_oid oid := (SELECT role_row.oid FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'authenticated');
  actual_booking_rows jsonb;
  actual_save_bilty_rpc jsonb;
  actual_service_role_acl jsonb;
  actual_service_role_effective jsonb;
  snapshot_row record;
  actual_policy_count bigint;
BEGIN
  SELECT * INTO snapshot_row FROM pg_temp.phase6a_bookings_migration_snapshot;

  SELECT COALESCE(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object('id', booking_row.id, 'row', pg_catalog.to_jsonb(booking_row))
      ORDER BY booking_row.id
    ), '[]'::jsonb
  )
  INTO actual_booking_rows
  FROM public.bookings AS booking_row;

  IF actual_booking_rows IS DISTINCT FROM snapshot_row.booking_rows THEN
    RAISE EXCEPTION 'SECURITY_PHASE6A_BOOKING_DATA_CHANGED';
  END IF;

  SELECT COALESCE(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'oid', procedure_row.oid,
        'schema', namespace_row.nspname,
        'name', procedure_row.proname,
        'identity_arguments', pg_catalog.pg_get_function_identity_arguments(procedure_row.oid),
        'identity_type_oids', procedure_row.proargtypes::text,
        'all_type_oids', procedure_row.proallargtypes::text,
        'argument_modes', procedure_row.proargmodes::text,
        'argument_names', procedure_row.proargnames::text,
        'default_count', procedure_row.pronargdefaults,
        'defaults_expression', pg_catalog.pg_get_expr(procedure_row.proargdefaults, 0),
        'return_type_oid', procedure_row.prorettype,
        'return_type', pg_catalog.format_type(procedure_row.prorettype, NULL),
        'owner', procedure_row.proowner,
        'owner_name', pg_catalog.pg_get_userbyid(procedure_row.proowner),
        'security_definer', procedure_row.prosecdef,
        'volatility', procedure_row.provolatile::text,
        'language', language_row.lanname,
        'kind', procedure_row.prokind::text,
        'normalized_config', COALESCE(ARRAY(
          SELECT pg_catalog.replace(
                   pg_catalog.regexp_replace(pg_catalog.lower(setting_row.setting), '[[:space:]]', '', 'g'),
                   '"', ''
                 )
          FROM pg_catalog.unnest(COALESCE(procedure_row.proconfig, ARRAY[]::text[])) AS setting_row(setting)
          ORDER BY 1
        ), ARRAY[]::text[]),
        'anon_execute', pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE'),
        'authenticated_execute', pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE'),
        'service_role_execute', pg_catalog.has_function_privilege('service_role', procedure_row.oid, 'EXECUTE'),
        'public_execute', EXISTS (
          SELECT 1
          FROM pg_catalog.aclexplode(COALESCE(
            procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner)
          )) AS acl_row
          WHERE acl_row.grantee = 0 AND acl_row.privilege_type = 'EXECUTE'
        ),
        'body_fingerprint', pg_catalog.md5(
          pg_catalog.replace(pg_catalog.replace(procedure_row.prosrc, E'\r\n', E'\n'), E'\r', E'\n')
        )
      ) ORDER BY procedure_row.oid
    ), '[]'::jsonb
  )
  INTO actual_save_bilty_rpc
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  JOIN pg_catalog.pg_language AS language_row
    ON language_row.oid = procedure_row.prolang
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.proname = 'save_bilty_with_items_v2';

  IF actual_save_bilty_rpc IS DISTINCT FROM snapshot_row.save_bilty_rpc THEN
    RAISE EXCEPTION 'SECURITY_PHASE6A_BILTY_RPC_CHANGED';
  END IF;

  SELECT COALESCE(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'grantor', acl_row.grantor,
        'privilege', acl_row.privilege_type,
        'grantable', acl_row.is_grantable
      ) ORDER BY acl_row.grantor, acl_row.privilege_type, acl_row.is_grantable
    ), '[]'::jsonb
  )
  INTO actual_service_role_acl
  FROM pg_catalog.pg_class AS relation_row
  CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(
    relation_row.relacl,
    pg_catalog.acldefault('r', relation_row.relowner)
  )) AS acl_row
  WHERE relation_row.oid = bookings_oid
    AND acl_row.grantee = (SELECT role_row.oid FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'service_role');

  actual_service_role_effective := pg_catalog.jsonb_build_object(
    'select', pg_catalog.has_table_privilege('service_role', 'public.bookings', 'SELECT'),
    'insert', pg_catalog.has_table_privilege('service_role', 'public.bookings', 'INSERT'),
    'update', pg_catalog.has_table_privilege('service_role', 'public.bookings', 'UPDATE'),
    'delete', pg_catalog.has_table_privilege('service_role', 'public.bookings', 'DELETE'),
    'truncate', pg_catalog.has_table_privilege('service_role', 'public.bookings', 'TRUNCATE'),
    'references', pg_catalog.has_table_privilege('service_role', 'public.bookings', 'REFERENCES'),
    'trigger', pg_catalog.has_table_privilege('service_role', 'public.bookings', 'TRIGGER')
  );

  IF actual_service_role_acl IS DISTINCT FROM snapshot_row.service_role_acl
     OR actual_service_role_effective IS DISTINCT FROM snapshot_row.service_role_effective THEN
    RAISE EXCEPTION 'SECURITY_PHASE6A_SERVICE_ROLE_PRIVILEGES_CHANGED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS relation_row
    WHERE relation_row.oid = bookings_oid
      AND relation_row.relrowsecurity
      AND NOT relation_row.relforcerowsecurity
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6A_RLS_POSTCONDITION_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_policy AS policy_row
    WHERE policy_row.polrelid = bookings_oid
      AND policy_row.polname IN (
        'Allow select on bookings', 'Allow insert on bookings', 'Allow update on bookings'
      )
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6A_OLD_BOOKINGS_POLICIES_REMAIN';
  END IF;

  SELECT pg_catalog.count(*)::bigint INTO actual_policy_count
  FROM pg_catalog.pg_policy AS policy_row
  WHERE policy_row.polrelid = bookings_oid;

  IF actual_policy_count <> 3
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_policy AS policy_row
       WHERE policy_row.polrelid = bookings_oid
         AND policy_row.polname = 'bookings_tenant_select'
         AND policy_row.polcmd = 'r'
         AND policy_row.polpermissive
         AND policy_row.polroles = ARRAY[authenticated_oid]
         AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid)), '[[:space:]()]', '', 'g') LIKE '%adda_idisnotnull%'
         AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid)), '[[:space:]()]', '', 'g') LIKE '%is_super_admin%or%current_user_adda_id%'
         AND pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid) ILIKE '%addas%'
         AND pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid) ILIKE '%adda_row.id%bookings.adda_id%'
         AND policy_row.polwithcheck IS NULL
     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_policy AS policy_row
       WHERE policy_row.polrelid = bookings_oid
         AND policy_row.polname = 'bookings_tenant_insert'
         AND policy_row.polcmd = 'a'
         AND policy_row.polpermissive
         AND policy_row.polroles = ARRAY[authenticated_oid]
         AND policy_row.polqual IS NULL
         AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid)), '[[:space:]()]', '', 'g') LIKE '%adda_idisnotnull%'
         AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid)), '[[:space:]()]', '', 'g') LIKE '%is_super_admin%or%current_user_adda_id%'
         AND pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid) ILIKE '%addas%'
         AND pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid) ILIKE '%adda_row.id%bookings.adda_id%'
     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_policy AS policy_row
       WHERE policy_row.polrelid = bookings_oid
         AND policy_row.polname = 'bookings_tenant_update'
         AND policy_row.polcmd = 'w'
         AND policy_row.polpermissive
         AND policy_row.polroles = ARRAY[authenticated_oid]
         AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid)), '[[:space:]()]', '', 'g') LIKE '%adda_idisnotnull%'
         AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid)), '[[:space:]()]', '', 'g') LIKE '%is_super_admin%or%current_user_adda_id%'
         AND pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid) ILIKE '%adda_row.id%bookings.adda_id%'
         AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid)), '[[:space:]()]', '', 'g') LIKE '%adda_idisnotnull%'
         AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid)), '[[:space:]()]', '', 'g') LIKE '%is_super_admin%or%current_user_adda_id%'
         AND pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid) ILIKE '%addas%'
         AND pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid) ILIKE '%adda_row.id%bookings.adda_id%'
     ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6A_TENANT_POLICY_POSTCONDITION_FAILED';
  END IF;

  IF pg_catalog.has_table_privilege('anon', bookings_oid, 'SELECT')
     OR pg_catalog.has_table_privilege('anon', bookings_oid, 'INSERT')
     OR pg_catalog.has_table_privilege('anon', bookings_oid, 'UPDATE')
     OR pg_catalog.has_table_privilege('anon', bookings_oid, 'DELETE')
     OR pg_catalog.has_table_privilege('anon', bookings_oid, 'TRUNCATE')
     OR pg_catalog.has_table_privilege('anon', bookings_oid, 'REFERENCES')
     OR pg_catalog.has_table_privilege('anon', bookings_oid, 'TRIGGER')
     OR EXISTS (
       SELECT 1
       FROM pg_catalog.pg_class AS relation_row
       CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(
         relation_row.relacl, pg_catalog.acldefault('r', relation_row.relowner)
       )) AS acl_row
       WHERE relation_row.oid = bookings_oid
         AND acl_row.grantee IN (0, (SELECT role_row.oid FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'anon'))
     )
     OR EXISTS (
       SELECT 1
       FROM pg_catalog.pg_attribute AS attribute_row
       CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_row.attacl) AS acl_row
       WHERE attribute_row.attrelid = bookings_oid
         AND attribute_row.attnum > 0
         AND NOT attribute_row.attisdropped
         AND acl_row.grantee IN (0, (SELECT role_row.oid FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'anon'))
     ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6A_ANON_OR_PUBLIC_PRIVILEGE_REMAINS';
  END IF;

  IF NOT pg_catalog.has_table_privilege('authenticated', bookings_oid, 'SELECT')
     OR NOT pg_catalog.has_table_privilege('authenticated', bookings_oid, 'INSERT')
     OR NOT pg_catalog.has_table_privilege('authenticated', bookings_oid, 'UPDATE')
     OR pg_catalog.has_table_privilege('authenticated', bookings_oid, 'DELETE')
     OR pg_catalog.has_table_privilege('authenticated', bookings_oid, 'TRUNCATE')
     OR pg_catalog.has_table_privilege('authenticated', bookings_oid, 'REFERENCES')
     OR pg_catalog.has_table_privilege('authenticated', bookings_oid, 'TRIGGER')
     OR EXISTS (
       SELECT 1
       FROM pg_catalog.pg_class AS relation_row
       CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(
         relation_row.relacl, pg_catalog.acldefault('r', relation_row.relowner)
       )) AS acl_row
       WHERE relation_row.oid = bookings_oid
         AND acl_row.grantee = authenticated_oid
         AND (acl_row.privilege_type NOT IN ('SELECT', 'INSERT', 'UPDATE') OR acl_row.is_grantable)
     )
     OR EXISTS (
       SELECT 1
       FROM pg_catalog.pg_attribute AS attribute_row
       CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_row.attacl) AS acl_row
       WHERE attribute_row.attrelid = bookings_oid
         AND attribute_row.attnum > 0
         AND NOT attribute_row.attisdropped
         AND acl_row.grantee = authenticated_oid
     ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6A_AUTHENTICATED_GRANTS_POSTCONDITION_FAILED';
  END IF;

  DROP TABLE pg_temp.phase6a_bookings_migration_snapshot;
END;
$phase6a_postconditions$;

COMMIT;
