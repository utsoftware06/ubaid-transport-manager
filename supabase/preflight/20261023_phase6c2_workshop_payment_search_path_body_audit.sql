-- Read-only: return the deployed Workshop payment RPC definition needed to
-- confirm that search_path can be narrowed without changing behavior.
SELECT
  namespace_row.nspname AS schema_name,
  procedure_row.proname AS function_name,
  pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
  pg_catalog.format('%I.%I(%s)', namespace_row.nspname, procedure_row.proname,
    pg_catalog.pg_get_function_identity_arguments(procedure_row.oid)) AS exact_signature,
  pg_catalog.pg_get_userbyid(procedure_row.proowner) AS owner_name,
  procedure_row.prosecdef AS security_definer,
  procedure_row.proconfig AS raw_proconfig,
  procedure_row.prosrc AS function_body,
  pg_catalog.pg_get_functiondef(procedure_row.oid) AS complete_definition,
  COALESCE(procedure_row.prosrc ~* '(^|[[:space:]])execute[[:space:]]+', false) AS contains_dynamic_sql,
  COALESCE(procedure_row.prosrc ~* 'public[.]is_super_admin[[:space:]]*[(]', false) AS qualified_super_admin_check,
  COALESCE(procedure_row.prosrc ~* 'public[.]current_user_adda_id[[:space:]]*[(]', false) AS qualified_current_adda_check,
  COALESCE(procedure_row.prosrc ~* 'public[.]workshops[[:space:]]+', false) AS public_workshops_reference_marker
FROM pg_catalog.pg_proc AS procedure_row
JOIN pg_catalog.pg_namespace AS namespace_row
  ON namespace_row.oid = procedure_row.pronamespace
WHERE procedure_row.oid = pg_catalog.to_regprocedure(
  'public.save_workshop_payment(bigint,uuid,date,numeric,numeric,text,text,text)'
);
