WITH column_contract AS (
  SELECT attribute_row.atttypid,
         attribute_row.atttypmod,
         attribute_row.attnotnull,
         pg_get_expr(default_row.adbin, default_row.adrelid) AS default_expression,
         constraint_row.conname,
         constraint_row.convalidated
  FROM pg_attribute AS attribute_row
  LEFT JOIN pg_attrdef AS default_row
    ON default_row.adrelid = attribute_row.attrelid
   AND default_row.adnum = attribute_row.attnum
  LEFT JOIN pg_constraint AS constraint_row
    ON constraint_row.conrelid = attribute_row.attrelid
   AND constraint_row.conname = 'bookings_detain_charges_nonnegative_check'
  WHERE attribute_row.attrelid = to_regclass('public.bookings')
    AND attribute_row.attname = 'detain_charges'
    AND attribute_row.attnum > 0
    AND NOT attribute_row.attisdropped
),
target_rpc AS (
  SELECT procedure_row.*
  FROM pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure('public.save_bilty_detain_charges(uuid,uuid,numeric)')
),
existing_bilty_rpc AS (
  SELECT procedure_row.*
  FROM pg_proc AS procedure_row
  JOIN pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.proname = 'save_bilty_with_items_v2'
    AND procedure_row.prorettype = 'uuid'::regtype
),
checks(check_name, expected, actual, passed) AS (
  SELECT 'DETAIN_COLUMN_CONTRACT'::text,
         'numeric NOT NULL DEFAULT 0 with nonnegative constraint'::text,
         coalesce((SELECT concat('type=', format_type(atttypid, atttypmod),
                                 ';not_null=', attnotnull,
                                 ';default=', default_expression,
                                 ';check=', conname,
                                 ';validated=', convalidated)
                   FROM column_contract), 'missing'),
         coalesce((SELECT atttypid = 'numeric'::regtype
                          AND attnotnull
                          AND default_expression IN ('0', '0::numeric')
                          AND conname = 'bookings_detain_charges_nonnegative_check'
                          AND convalidated
                   FROM column_contract), false)

  UNION ALL

  SELECT 'SAVE_RPC_SECURITY_AND_SCOPE',
         'fixed-path SECURITY DEFINER RPC validates active role and explicit Adda/Booking scope',
         coalesce((SELECT concat('exists=true;definer=', prosecdef,
                                 ';path=', coalesce(array_to_string(proconfig, ','), 'unset'))
                   FROM target_rpc), 'missing'),
         coalesce((SELECT prosecdef
                          AND (proconfig @> ARRAY['search_path=""'] OR proconfig @> ARRAY['search_path='])
                          AND pg_get_functiondef(oid) ILIKE '%profile.id = auth.uid()%'
                          AND pg_get_functiondef(oid) ILIKE '%caller_adda_id IS DISTINCT FROM p_adda_id%'
                          AND pg_get_functiondef(oid) ILIKE '%booking.id = p_bilty_id%'
                          AND pg_get_functiondef(oid) ILIKE '%booking.adda_id = p_adda_id%'
                   FROM target_rpc), false)

  UNION ALL

  SELECT 'SAVE_RPC_GRANTS',
         'authenticated execute only; anon/PUBLIC revoked',
         coalesce((SELECT concat('authenticated=', has_function_privilege('authenticated', oid, 'EXECUTE'),
                                 ';anon=', has_function_privilege('anon', oid, 'EXECUTE'),
                                 ';public=', EXISTS (
                                   SELECT 1 FROM aclexplode(coalesce(proacl, acldefault('f', proowner))) AS acl_row
                                   WHERE acl_row.grantee = 0 AND acl_row.privilege_type = 'EXECUTE'
                                 ))
                   FROM target_rpc), 'missing'),
         coalesce((SELECT has_function_privilege('authenticated', oid, 'EXECUTE')
                          AND NOT has_function_privilege('anon', oid, 'EXECUTE')
                          AND NOT EXISTS (
                            SELECT 1 FROM aclexplode(coalesce(proacl, acldefault('f', proowner))) AS acl_row
                            WHERE acl_row.grantee = 0 AND acl_row.privilege_type = 'EXECUTE'
                          )
                   FROM target_rpc), false)

  UNION ALL

  SELECT 'LEGACY_BILTY_SAVE_PRESERVED',
         'save_bilty_with_items_v2 remains UUID-returning',
         coalesce((SELECT oid::regprocedure::text FROM existing_bilty_rpc LIMIT 1), 'missing'),
         EXISTS (SELECT 1 FROM existing_bilty_rpc)
),
final_rows AS (
  SELECT check_name, expected, actual, passed FROM checks
  UNION ALL
  SELECT 'BILTY_DETAIN_CHARGES_OVERALL',
         'all mandatory Bilty Detain Charges contracts pass',
         concat('mandatory_failures=', count(*) FILTER (WHERE NOT passed)),
         bool_and(passed)
  FROM checks
)
SELECT check_name, expected, actual,
       CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM final_rows
ORDER BY CASE WHEN check_name = 'BILTY_DETAIN_CHARGES_OVERALL' THEN 1 ELSE 0 END, check_name;
