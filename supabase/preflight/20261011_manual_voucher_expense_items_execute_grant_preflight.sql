-- READ ONLY: verify the exact RPC exists and retains its protected function contract.
WITH target AS (
  SELECT procedure_row.oid,
    procedure_row.prosecdef,
    procedure_row.provolatile,
    procedure_row.proconfig,
    pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments
  FROM (SELECT pg_catalog.to_regprocedure(
    'public.save_manual_voucher_expense_items(bigint,jsonb)') AS oid) requested
  LEFT JOIN pg_catalog.pg_proc procedure_row ON procedure_row.oid=requested.oid
)
SELECT
  'SAVE_RPC_PATCH_TARGET'::text AS check_name,
  'Exact bigint,jsonb RPC exists as SECURITY DEFINER VOLATILE with empty search_path'::text AS expected,
  pg_catalog.format('exists=%s; identity=%s; security_definer=%s; volatile=%s; empty_search_path=%s',
    oid IS NOT NULL,
    coalesce(identity_arguments,'<missing>'),
    coalesce(prosecdef,false),
    coalesce(provolatile='v',false),
    coalesce(proconfig @> ARRAY['search_path=""']::text[],false)) AS actual,
  CASE WHEN oid IS NOT NULL AND prosecdef AND provolatile='v'
         AND proconfig @> ARRAY['search_path=""']::text[]
    THEN 'PASS' ELSE 'FAIL' END AS result
FROM target;
