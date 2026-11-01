WITH target AS (
  SELECT pg_catalog.to_regprocedure(
    'public.get_broker_loading_history(uuid,uuid,date,date,text,integer,integer)'
  ) AS function_oid
), function_row AS (
  SELECT proc_row.oid,
         proc_row.prosecdef,
         proc_row.proretset,
         proc_row.prorettype,
         proc_row.proconfig,
         proc_row.prosrc,
         proc_row.proacl,
         proc_row.proowner,
         proc_row.proargnames,
         owner_role.rolname AS owner_name
  FROM target
  LEFT JOIN pg_catalog.pg_proc AS proc_row ON proc_row.oid=target.function_oid
  LEFT JOIN pg_catalog.pg_roles AS owner_role ON owner_role.oid=proc_row.proowner
), facts AS (
  SELECT function_row.*,
         COALESCE(pg_catalog.has_function_privilege('authenticated',function_row.oid,'EXECUTE'),false) AS authenticated_execute,
         COALESCE(pg_catalog.has_function_privilege('anon',function_row.oid,'EXECUTE'),false) AS anon_execute,
         COALESCE(pg_catalog.has_function_privilege('service_role',function_row.oid,'EXECUTE'),false) AS service_role_execute,
         EXISTS (
           SELECT 1
           FROM pg_catalog.aclexplode(COALESCE(
             function_row.proacl,
             pg_catalog.acldefault('f',function_row.proowner)
           )) AS acl
           WHERE acl.grantee=0::pg_catalog.oid AND acl.privilege_type='EXECUTE'
         ) AS public_execute,
         COALESCE(function_row.prosrc,'') AS body
  FROM function_row
), checks AS (
  SELECT 'RPC_EXISTS_AND_SIGNATURE'::text AS check_name,
         'public.get_broker_loading_history(uuid,uuid,date,date,text,integer,integer)'::text AS expected,
         CASE WHEN facts.oid IS NOT NULL THEN 'exists' ELSE 'missing' END AS actual,
         facts.oid IS NOT NULL AS passed
  FROM facts
  UNION ALL
  SELECT 'SECURITY_DEFINER_OWNER', 'SECURITY DEFINER; owner postgres',
         COALESCE(facts.prosecdef::text,'missing') || '; owner ' || COALESCE(facts.owner_name,'missing'),
         COALESCE(facts.prosecdef AND facts.owner_name='postgres',false)
  FROM facts
  UNION ALL
  SELECT 'RPC_ARGUMENT_NAMES', 'p_adda_id,p_broker_id,p_from_date,p_to_date,p_search,p_limit,p_offset',
         COALESCE(facts.proargnames[1:7]::text,'missing'),
         COALESCE(facts.proargnames[1:7]=ARRAY[
           'p_adda_id','p_broker_id','p_from_date','p_to_date','p_search','p_limit','p_offset'
         ]::text[],false)
  FROM facts
  UNION ALL
  SELECT 'SAFE_SEARCH_PATH', 'search_path=pg_catalog only',
         COALESCE(facts.proconfig::text,'unset'),
         COALESCE(facts.proconfig=ARRAY['search_path=pg_catalog']::text[],false)
  FROM facts
  UNION ALL
  SELECT 'EXECUTE_ACL', 'authenticated=true; service_role=true; anon=false; PUBLIC=false',
         'authenticated=' || facts.authenticated_execute::text ||
         '; service_role=' || facts.service_role_execute::text ||
         '; anon=' || facts.anon_execute::text ||
         '; PUBLIC=' || facts.public_execute::text,
         facts.authenticated_execute AND facts.service_role_execute
         AND NOT facts.anon_execute AND NOT facts.public_execute
  FROM facts
  UNION ALL
  SELECT 'READ_ONLY_SOURCE_CONTRACT',
         'active Adda authorization; selected Broker belongs to Adda; Booking broker_id -> Loading booking_id; gross Kiraya and existing commission; no DML',
         'helper=' || (pg_catalog.strpos(facts.body,'public.ut_loading_brokerage_authorize')>0)::text ||
         '; broker_link=' || (pg_catalog.strpos(facts.body,'booking.broker_id=p_broker_id')>0)::text ||
         '; broker_tenant=' || (pg_catalog.strpos(facts.body,'linked_broker.adda_id=booking.adda_id')>0)::text ||
         '; loading_link=' || (pg_catalog.strpos(facts.body,'loading.booking_id=booking.id')>0)::text ||
         '; gross=' || (pg_catalog.strpos(facts.body,'booking.vehicle_freight')>0)::text ||
         '; commission=' || (pg_catalog.strpos(facts.body,'booking.broker_commission')>0)::text ||
         '; write_sql=' || (facts.body ~* '(^|[;[:space:]])(insert[[:space:]]+into|update[[:space:]]+[[:alnum:]_\.]+|delete[[:space:]]+from|truncate[[:space:]])')::text,
         pg_catalog.strpos(facts.body,'public.ut_loading_brokerage_authorize')>0
         AND pg_catalog.strpos(facts.body,'booking.broker_id=p_broker_id')>0
         AND pg_catalog.strpos(facts.body,'linked_broker.adda_id=booking.adda_id')>0
         AND pg_catalog.strpos(facts.body,'loading.booking_id=booking.id')>0
         AND pg_catalog.strpos(facts.body,'booking.vehicle_freight')>0
         AND pg_catalog.strpos(facts.body,'booking.broker_commission')>0
         AND NOT (facts.body ~* '(^|[;[:space:]])(insert[[:space:]]+into|update[[:space:]]+[[:alnum:]_\.]+|delete[[:space:]]+from|truncate[[:space:]])')
  FROM facts
  UNION ALL
  SELECT 'READ_ONLY_RESULT_CONTRACT',
         'TABLE(history_row_id text, history_date date, booking_id uuid, booking_no text, booking_date date, bilty_loading_date date, loading_id bigint, loading_no text, loading_date date, route text, from_city text, to_city text, vehicle_no text, driver_name text, gross_kiraya numeric, loading_brokerage numeric, booking_status text, loading_status text, loading_payment_status text, total_count bigint)',
         'proretset=' || COALESCE(facts.proretset::text,'missing') ||
         '; result=' || COALESCE(pg_catalog.pg_get_function_result(facts.oid),'missing'),
         COALESCE(
           facts.proretset
           AND facts.prorettype='record'::pg_catalog.regtype
           AND pg_catalog.lower(pg_catalog.regexp_replace(
             pg_catalog.pg_get_function_result(facts.oid),'[[:space:]]','','g'
           ))=pg_catalog.lower(pg_catalog.regexp_replace(
             'TABLE(history_row_id text, history_date date, booking_id uuid, booking_no text, booking_date date, bilty_loading_date date, loading_id bigint, loading_no text, loading_date date, route text, from_city text, to_city text, vehicle_no text, driver_name text, gross_kiraya numeric, loading_brokerage numeric, booking_status text, loading_status text, loading_payment_status text, total_count bigint)',
             '[[:space:]]','','g'
           )),false)
  FROM facts
), report AS (
  SELECT checks.check_name,checks.expected,checks.actual,
         CASE WHEN checks.passed THEN 'PASS' ELSE 'FAIL' END AS result
  FROM checks
)
SELECT report.check_name,report.expected,report.actual,report.result
FROM report
UNION ALL
SELECT 'OVERALL',
       'all checks pass',
       'failed_checks=' || pg_catalog.count(*) FILTER (WHERE report.result='FAIL')::text,
       CASE WHEN pg_catalog.count(*) FILTER (WHERE report.result='FAIL')=0 THEN 'PASS' ELSE 'FAIL' END
FROM report;
