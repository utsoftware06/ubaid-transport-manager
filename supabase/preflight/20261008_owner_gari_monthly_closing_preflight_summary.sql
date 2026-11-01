-- Phase 6 compact preflight. READ ONLY; returns exactly one result grid.
-- Repository-only observations are labeled WARN because SQL cannot verify files.

WITH
relations AS (
  SELECT
    pg_catalog.to_regclass('public.owner_gari_accounts') AS accounts_oid,
    pg_catalog.to_regclass('public.owner_gari_account_transactions') AS transactions_oid
),
columns AS (
  SELECT relation_value.relname, attribute_row.attname,
    pg_catalog.format_type(attribute_row.atttypid, attribute_row.atttypmod) AS data_type,
    attribute_row.attnotnull
  FROM relations
  CROSS JOIN LATERAL (VALUES
    (accounts_oid, 'owner_gari_accounts'),
    (transactions_oid, 'owner_gari_account_transactions')
  ) AS relation_value(relation_oid, relname)
  JOIN pg_catalog.pg_attribute AS attribute_row
    ON attribute_row.attrelid=relation_value.relation_oid
   AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped
),
constraints AS (
  SELECT conname::text AS conname, contype::text AS contype, convalidated,
    pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_constraintdef(oid,true)), '[[:space:]]+', ' ', 'g') AS definition
  FROM pg_catalog.pg_constraint
  WHERE conrelid IN (SELECT accounts_oid FROM relations UNION ALL SELECT transactions_oid FROM relations)
),
indexes AS (
  SELECT index_class.relname::text AS index_name, index_row.indisunique, index_row.indisvalid, index_row.indisready
  FROM pg_catalog.pg_index index_row
  JOIN pg_catalog.pg_class index_class ON index_class.oid=index_row.indexrelid
  JOIN pg_catalog.pg_namespace index_namespace ON index_namespace.oid=index_class.relnamespace
  WHERE index_namespace.nspname='public'
    AND index_class.relname IN (
      'owner_gari_transactions_chakkar_source_uidx','owner_gari_transactions_opening_seed_uidx',
      'owner_gari_transactions_adjustment_source_uidx','owner_gari_transactions_commission_source_uidx',
      'owner_gari_transactions_withdrawal_idempotency_uidx',
      'owner_gari_transactions_account_date_idx','owner_gari_transactions_vehicle_date_idx'
    )
),
policies AS (
  SELECT policy_row.polrelid, policy_row.polcmd::text AS polcmd, policy_row.polroles,
    pg_catalog.pg_get_expr(policy_row.polqual,policy_row.polrelid) AS using_expression
  FROM pg_catalog.pg_policy policy_row
  WHERE policy_row.polrelid IN (SELECT accounts_oid FROM relations UNION ALL SELECT transactions_oid FROM relations)
),
triggers AS (
  SELECT trigger_row.tgname::text AS trigger_name,trigger_row.tgenabled::text AS enabled,trigger_row.tgisinternal,trigger_row.tgtype,
    procedure_row.proname::text AS function_name
  FROM pg_catalog.pg_trigger trigger_row
  JOIN pg_catalog.pg_class relation_row ON relation_row.oid=trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=relation_row.relnamespace
  JOIN pg_catalog.pg_proc procedure_row ON procedure_row.oid=trigger_row.tgfoid
  WHERE namespace_row.nspname='public' AND relation_row.relname='owner_gari_account_transactions'
    AND trigger_row.tgname::text IN (
      'owner_gari_account_transactions_protect','owner_gari_commission_transactions_append_only',
      'owner_gari_commission_transactions_no_truncate')
),
routines AS (
  SELECT routine_name, routine_oid, procedure_row.prosecdef, procedure_row.proconfig,
    pg_catalog.regexp_replace(pg_catalog.lower(coalesce(CASE WHEN routine_oid IS NOT NULL THEN pg_catalog.pg_get_functiondef(routine_oid::oid) END,'')), '[[:space:]]+', ' ', 'g') AS body
  FROM (VALUES
    ('v1',pg_catalog.to_regprocedure('public.get_owner_gari_account_statement(uuid,date,date,date,text,uuid,text)')),
    ('v2',pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v2(uuid,date,date,date,text,uuid,text)')),
    ('v3',pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)'))
  ) expected(routine_name,routine_oid)
  LEFT JOIN pg_catalog.pg_proc procedure_row ON procedure_row.oid=routine_oid
),
checks(check_name,expected,actual,result,is_mandatory) AS (
  SELECT 'OWNER_GARI_TABLES','Both account and transaction tables exist',
    'accounts='||coalesce(accounts_oid::text,'missing')||'; transactions='||coalesce(transactions_oid::text,'missing'),
    CASE WHEN accounts_oid IS NOT NULL AND transactions_oid IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,true
  FROM relations

  UNION ALL
  SELECT 'AUTHORITATIVE_SOURCE_TABLES','Vehicle, Chakkar, voucher adjustment and commission source tables exist',
    'vehicles='||coalesce(pg_catalog.to_regclass('public.vehicles')::text,'missing')
      ||'; chakkar='||coalesce(pg_catalog.to_regclass('public.vehicle_chakkar_settlements')::text,'missing')
      ||'; voucher_adjustments='||coalesce(pg_catalog.to_regclass('public.voucher_adjustments')::text,'missing')
      ||'; commission_events='||coalesce(pg_catalog.to_regclass('public.adda_vehicle_commission_events')::text,'missing'),
    CASE WHEN pg_catalog.to_regclass('public.vehicles') IS NOT NULL
      AND pg_catalog.to_regclass('public.vehicle_chakkar_settlements') IS NOT NULL
      AND pg_catalog.to_regclass('public.voucher_adjustments') IS NOT NULL
      AND pg_catalog.to_regclass('public.adda_vehicle_commission_events') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,true
  FROM relations

  UNION ALL
  SELECT 'ACCOUNT_TRANSACTION_SCHEMA','Expected UUID tenant/account/vehicle IDs, transaction_date date, transaction_type text, amount numeric(14,2)',
    coalesce((SELECT string_agg(relname||'.'||attname::text||'='||data_type||CASE WHEN attnotnull THEN ' NOT NULL' ELSE '' END,'; ' ORDER BY relname,attname)
      FROM columns WHERE attname IN ('id','account_id','adda_id','vehicle_id','transaction_date','transaction_type','amount')),'required columns missing'),
    CASE WHEN (SELECT count(*) FROM columns WHERE
      (relname='owner_gari_accounts' AND attname IN ('id','adda_id','vehicle_id') AND data_type='uuid' AND attnotnull)
      OR (relname='owner_gari_account_transactions' AND attname IN ('id','account_id','adda_id','vehicle_id') AND data_type='uuid' AND attnotnull)
      OR (relname='owner_gari_account_transactions' AND attname='transaction_date' AND data_type='date' AND attnotnull)
      OR (relname='owner_gari_account_transactions' AND attname='transaction_type' AND data_type='text' AND attnotnull)
      OR (relname='owner_gari_account_transactions' AND attname='amount' AND data_type='numeric(14,2)' AND attnotnull))=10
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM relations

  UNION ALL
  SELECT 'SIGNED_AMOUNT_CONTRACT','Positive amounts credit and negative amounts debit',
    coalesce(pg_catalog.obj_description(transactions_oid,'pg_class'),'table signed-amount comment missing'),
    CASE WHEN transactions_oid IS NOT NULL AND pg_catalog.obj_description(transactions_oid,'pg_class') ILIKE '%positive%credit%negative%debit%' THEN 'PASS' ELSE 'FAIL' END,true
  FROM relations

  UNION ALL
  SELECT 'ALL_TRANSACTION_TYPES','Legacy, voucher and Phase 5B correction transaction types remain allowed',
    coalesce((SELECT definition FROM constraints WHERE conname='owner_gari_transactions_type_check'),'type constraint missing'),
    CASE WHEN EXISTS(SELECT 1 FROM constraints WHERE conname='owner_gari_transactions_type_check'
      AND definition LIKE '%opening_seed%' AND definition LIKE '%chakkar_net_credit%'
      AND definition LIKE '%owner_withdrawal%' AND definition LIKE '%gari_withdrawal%'
      AND definition ~ '(^|[^a-z0-9_])monthly_adda_commission([^a-z0-9_]|$)'
      AND definition LIKE '%monthly_adda_commission_reversal%'
      AND definition LIKE '%monthly_adda_commission_reissue%'
      AND definition LIKE '%monthly_adda_commission_adjustment_increase%'
      AND definition LIKE '%monthly_adda_commission_adjustment_decrease%'
      AND definition LIKE '%monthly_adda_commission_correction_reversal_credit%'
      AND definition LIKE '%monthly_adda_commission_correction_reversal_debit%'
      AND definition LIKE '%adjustment_credit%' AND definition LIKE '%adjustment_debit%'
      AND definition LIKE '%voucher_adjustment_expense%') THEN 'PASS' ELSE 'FAIL' END,true
  FROM relations

  UNION ALL
  SELECT 'PHASE5B_COMMISSION_SIGN_SOURCE','Commission correction source IDs and all debit/credit signs are guarded',
    'source='||coalesce((SELECT conname::text||': '||definition FROM constraints WHERE conname='owner_gari_transactions_commission_source_check'),'missing')
      ||'; amount='||coalesce((SELECT conname::text||': '||definition FROM constraints WHERE conname='owner_gari_transactions_commission_amount_check'),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM constraints WHERE conname='owner_gari_transactions_commission_source_check'
      AND definition LIKE '%source_commission_event_id is not null%' AND definition LIKE '%source_settlement_id is null%' AND definition LIKE '%source_adjustment_id is null%'
      AND definition ~ '(^|[^a-z0-9_])monthly_adda_commission([^a-z0-9_]|$)'
      AND definition LIKE '%monthly_adda_commission_reversal%'
      AND definition LIKE '%monthly_adda_commission_reissue%'
      AND definition LIKE '%monthly_adda_commission_adjustment_increase%'
      AND definition LIKE '%monthly_adda_commission_adjustment_decrease%'
      AND definition LIKE '%monthly_adda_commission_correction_reversal_credit%'
      AND definition LIKE '%monthly_adda_commission_correction_reversal_debit%')
      AND EXISTS(SELECT 1 FROM constraints WHERE conname='owner_gari_transactions_commission_amount_check'
      AND pg_catalog.replace(definition,'(0)::numeric','0') LIKE '%amount < 0%'
      AND pg_catalog.replace(definition,'(0)::numeric','0') LIKE '%amount > 0%'
      AND substring(definition FROM 1 FOR pg_catalog.strpos(definition,'amount <')) ~ 'monthly_adda_commission([^a-z0-9_]|$)'
      AND substring(definition FROM 1 FOR pg_catalog.strpos(definition,'amount <')) LIKE '%monthly_adda_commission_reissue%'
      AND substring(definition FROM 1 FOR pg_catalog.strpos(definition,'amount <')) LIKE '%monthly_adda_commission_adjustment_increase%'
      AND substring(definition FROM 1 FOR pg_catalog.strpos(definition,'amount <')) LIKE '%monthly_adda_commission_correction_reversal_debit%'
      AND substring(definition FROM pg_catalog.strpos(definition,'amount <') FOR pg_catalog.strpos(definition,'amount >')-pg_catalog.strpos(definition,'amount <')) LIKE '%monthly_adda_commission_reversal%'
      AND substring(definition FROM pg_catalog.strpos(definition,'amount <') FOR pg_catalog.strpos(definition,'amount >')-pg_catalog.strpos(definition,'amount <')) LIKE '%monthly_adda_commission_adjustment_decrease%'
      AND substring(definition FROM pg_catalog.strpos(definition,'amount <') FOR pg_catalog.strpos(definition,'amount >')-pg_catalog.strpos(definition,'amount <')) LIKE '%monthly_adda_commission_correction_reversal_credit%') THEN 'PASS' ELSE 'FAIL' END,true
  FROM relations

  UNION ALL
  SELECT 'VOUCHER_EXPENSE_SIGN','Voucher adjustment is a negative signed debit',
    coalesce((SELECT definition FROM constraints WHERE conname='owner_gari_transactions_adjustment_amount_check'),'voucher sign check missing'),
    CASE WHEN EXISTS(SELECT 1 FROM constraints WHERE conname='owner_gari_transactions_adjustment_amount_check'
      AND definition LIKE '%voucher_adjustment_expense%'
      AND pg_catalog.replace(definition,'(0)::numeric','0') LIKE '%amount < 0%') THEN 'PASS' ELSE 'FAIL' END,true
  FROM relations

  UNION ALL
  SELECT 'TENANT_VEHICLE_RELATIONSHIPS','One account per Adda/vehicle; account and source FKs validate same Adda and vehicle',
    coalesce((SELECT string_agg(conname::text||'='||definition,' | ' ORDER BY conname) FROM constraints WHERE conname IN (
      'owner_gari_transactions_account_fkey','owner_gari_transactions_settlement_fkey',
      'owner_gari_transactions_adjustment_fkey','owner_gari_transactions_commission_source_fkey',
      'owner_gari_accounts_vehicle_adda_fkey','owner_gari_accounts_vehicle_key','owner_gari_accounts_id_adda_vehicle_key')),'tenant/vehicle constraints missing'),
    CASE WHEN (SELECT count(*) FROM constraints WHERE conname IN (
      'owner_gari_transactions_account_fkey','owner_gari_transactions_settlement_fkey',
      'owner_gari_transactions_adjustment_fkey','owner_gari_transactions_commission_source_fkey',
      'owner_gari_accounts_vehicle_adda_fkey') AND contype='f' AND convalidated
      AND definition LIKE '%adda_id%' AND definition LIKE '%vehicle_id%')=5
      AND EXISTS(SELECT 1 FROM constraints WHERE conname='owner_gari_accounts_vehicle_key'
        AND contype='u' AND definition LIKE '%unique (adda_id, vehicle_id)%')
      AND EXISTS(SELECT 1 FROM constraints WHERE conname='owner_gari_accounts_id_adda_vehicle_key'
        AND contype='u' AND definition LIKE '%unique (id, adda_id, vehicle_id)%')
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM relations

  UNION ALL
  SELECT 'RLS_AND_BROWSER_WRITES','RLS and tenant-read policies active; authenticated direct DML blocked',
    'accounts_rls='||coalesce((SELECT relrowsecurity::text FROM pg_catalog.pg_class WHERE oid=accounts_oid),'missing')
      ||'; transaction_rls='||coalesce((SELECT relrowsecurity::text FROM pg_catalog.pg_class WHERE oid=transactions_oid),'missing')
      ||'; authenticated_dml='||CASE WHEN transactions_oid IS NOT NULL AND (
        pg_catalog.has_table_privilege('authenticated',transactions_oid,'INSERT') OR pg_catalog.has_table_privilege('authenticated',transactions_oid,'UPDATE')
        OR pg_catalog.has_table_privilege('authenticated',transactions_oid,'DELETE') OR pg_catalog.has_table_privilege('authenticated',transactions_oid,'TRUNCATE')) THEN 'granted' ELSE 'blocked' END,
    CASE WHEN (SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid=accounts_oid) IS TRUE
      AND (SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid=transactions_oid) IS TRUE
      AND (SELECT count(*) FROM policies WHERE polcmd='r'
        AND (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='authenticated')=ANY(polroles)
        AND using_expression ILIKE '%is_super_admin%'
        AND using_expression ILIKE '%current_user_adda_id%')>=2
      AND transactions_oid IS NOT NULL
      AND NOT pg_catalog.has_table_privilege('authenticated',transactions_oid,'INSERT')
      AND NOT pg_catalog.has_table_privilege('authenticated',transactions_oid,'UPDATE')
      AND NOT pg_catalog.has_table_privilege('authenticated',transactions_oid,'DELETE')
      AND NOT pg_catalog.has_table_privilege('authenticated',transactions_oid,'TRUNCATE')
      AND NOT pg_catalog.has_table_privilege('anon',transactions_oid,'INSERT')
      AND NOT pg_catalog.has_table_privilege('anon',transactions_oid,'UPDATE')
      AND NOT pg_catalog.has_table_privilege('anon',transactions_oid,'DELETE')
      AND NOT pg_catalog.has_table_privilege('anon',transactions_oid,'TRUNCATE')
      AND NOT pg_catalog.has_table_privilege('authenticated',accounts_oid,'INSERT')
      AND NOT pg_catalog.has_table_privilege('authenticated',accounts_oid,'UPDATE')
      AND NOT pg_catalog.has_table_privilege('authenticated',accounts_oid,'DELETE')
      AND NOT pg_catalog.has_table_privilege('authenticated',accounts_oid,'TRUNCATE')
      AND NOT pg_catalog.has_table_privilege('anon',accounts_oid,'INSERT')
      AND NOT pg_catalog.has_table_privilege('anon',accounts_oid,'UPDATE')
      AND NOT pg_catalog.has_table_privilege('anon',accounts_oid,'DELETE')
      AND NOT pg_catalog.has_table_privilege('anon',accounts_oid,'TRUNCATE') THEN 'PASS' ELSE 'FAIL' END,true
  FROM relations

  UNION ALL
  SELECT 'COMMISSION_APPEND_ONLY_GUARDS','Enabled row update/delete guard and truncate guard protect commission projections',
    coalesce((SELECT string_agg(trigger_name||'->'||function_name||'; enabled='||enabled||'; internal='||tgisinternal::text,' | ' ORDER BY trigger_name) FROM triggers),'commission guards missing'),
    CASE WHEN EXISTS(SELECT 1 FROM triggers WHERE NOT tgisinternal AND enabled<>'D'
        AND trigger_name='owner_gari_account_transactions_protect' AND function_name='ut_protect_owner_gari_foundation')
      AND EXISTS(SELECT 1 FROM triggers WHERE NOT tgisinternal AND enabled<>'D'
        AND trigger_name='owner_gari_commission_transactions_append_only'
        AND function_name='ut_guard_owner_gari_commission_append_only'
        AND (tgtype & 1)=1 AND (tgtype & 2)=2 AND (tgtype & 4)=4 AND (tgtype & 8)=8 AND (tgtype & 16)=16)
      AND EXISTS(SELECT 1 FROM triggers WHERE NOT tgisinternal AND enabled<>'D'
        AND trigger_name='owner_gari_commission_transactions_no_truncate'
        AND function_name='ut_guard_owner_gari_commission_append_only'
        AND (tgtype & 2)=2 AND (tgtype & 32)=32 AND (tgtype & 1)=0)
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM relations

  UNION ALL
  SELECT 'STATEMENT_RPC_SECURITY','Statement v1/v2/v3 exist, SECURITY DEFINER, empty search_path; authenticated read allowed, anon denied',
    coalesce((SELECT string_agg(routine_name||': exists='||(routine_oid IS NOT NULL)::text||'; definer='||coalesce(prosecdef::text,'false')||'; config='||coalesce(proconfig::text,'[]'),'; ' ORDER BY routine_name) FROM routines),'RPCs missing'),
    CASE WHEN (SELECT count(*) FROM routines WHERE routine_oid IS NOT NULL AND prosecdef
      AND EXISTS(SELECT 1 FROM unnest(coalesce(proconfig,ARRAY[]::text[])) setting WHERE setting IN ('search_path=""','search_path='))
      AND pg_catalog.has_function_privilege('authenticated',routine_oid,'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon',routine_oid,'EXECUTE'))=3 THEN 'PASS' ELSE 'FAIL' END,true
  FROM relations

  UNION ALL
  SELECT 'STATEMENT_TENANT_AUTHORIZATION','Read RPC enforces active identity/role and Adda scoping with Super Admin branch',
    coalesce((SELECT body FROM routines WHERE routine_name='v1'),'v1 missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routines WHERE routine_name='v1'
      AND body LIKE '%current_user_role()%'
      AND body LIKE '%super_admin%' AND body LIKE '%adda_admin%' AND body LIKE '%operator%'
      AND body LIKE '%is_super_admin()%'
      AND body LIKE '%current_user_adda_id()%'
      AND body LIKE '%vehicle_row.adda_id%') THEN 'PASS' ELSE 'FAIL' END,true
  FROM relations

  UNION ALL
  SELECT 'OPENING_CLOSING_AND_DATE','Opening is signed sum before period; closing uses signed period net; transaction_date is accounting date',
    coalesce((SELECT body FROM routines WHERE routine_name='v1'),'v1 missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routines WHERE routine_name='v1'
      AND body LIKE '%ledger.transaction_date<period_start%'
      AND body LIKE '%opening.opening_balance+period_totals.period_net_change%'
      AND body LIKE '%order by ledger.transaction_date,ledger.created_at,ledger.transaction_id%') THEN 'PASS' ELSE 'FAIL' END,true
  FROM relations

  UNION ALL
  SELECT 'FILTER_AND_PERIOD_TOTALS','Search/type filters do not change month summary; period uses accounting date rows',
    coalesce((SELECT body FROM routines WHERE routine_name='v1'),'v1 missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routines WHERE routine_name='v1'
      AND body LIKE '%period_totals as (%' AND body LIKE '%from period_rows period_row%' AND body LIKE '%filtered_rows as (%') THEN 'PASS' ELSE 'FAIL' END,true
  FROM relations

  UNION ALL
  SELECT 'PHASE5B_COMMISSION_RECONCILIATION','Statement v3 includes all correction signs in net commission and links event lineage',
    coalesce((SELECT body FROM routines WHERE routine_name='v3'),'v3 missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routines WHERE routine_name='v3'
      AND body LIKE '%monthly_adda_commission_reissue%'
      AND body LIKE '%monthly_adda_commission_adjustment_increase%'
      AND body LIKE '%monthly_adda_commission_adjustment_decrease%'
      AND body LIKE '%monthly_adda_commission_correction_reversal_credit%'
      AND body LIKE '%monthly_adda_commission_correction_reversal_debit%'
      AND body LIKE '%commission_effective_root_amount%' AND body LIKE '%commission_root_event_id%') THEN 'PASS' ELSE 'FAIL' END,true
  FROM relations

  UNION ALL
  SELECT 'SOURCE_UNIQUENESS_AND_INDEXES','Unique source/idempotency indexes and transaction-date account indexes are valid',
    coalesce((SELECT string_agg(index_name::text||'; unique='||indisunique::text||'; valid='||indisvalid::text,' | ' ORDER BY index_name) FROM indexes),'indexes missing'),
    CASE WHEN (SELECT count(*) FROM indexes WHERE index_name IN (
      'owner_gari_transactions_chakkar_source_uidx','owner_gari_transactions_opening_seed_uidx',
      'owner_gari_transactions_adjustment_source_uidx','owner_gari_transactions_commission_source_uidx',
      'owner_gari_transactions_withdrawal_idempotency_uidx') AND indisunique AND indisvalid AND indisready)=5
      AND (SELECT count(*) FROM indexes WHERE index_name IN (
      'owner_gari_transactions_account_date_idx','owner_gari_transactions_vehicle_date_idx') AND indisvalid AND indisready)=2
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM relations

  UNION ALL
  SELECT 'CASHBOOK_INDEPENDENCE','Owner/Gari balance statement does not read Cashbook',
    coalesce((SELECT string_agg(routine_name||': cashbook_reference='||(body LIKE '%cashbook%')::text,'; ' ORDER BY routine_name) FROM routines),'RPCs missing'),
    CASE WHEN (SELECT count(*) FROM routines WHERE routine_oid IS NOT NULL AND body NOT LIKE '%cashbook%')=3 THEN 'PASS' ELSE 'FAIL' END,true
  FROM relations

  UNION ALL
  SELECT 'PROPOSED_RPC_COLLISION','Proposed monthly closing RPC signature is available',
    coalesce(pg_catalog.to_regprocedure('public.get_owner_gari_monthly_closing_v1(uuid,uuid,date,text,text)')::text,'no collision'),
    CASE WHEN pg_catalog.to_regprocedure('public.get_owner_gari_monthly_closing_v1(uuid,uuid,date,text,text)') IS NULL THEN 'PASS' ELSE 'FAIL' END,true
  FROM relations

  UNION ALL
  SELECT 'REPO_PRINT_AND_FILTER_BEHAVIOR','Print should identify filtered detail while retaining complete monthly totals',
    'Repository: search/type filters are passed to statement_v3; summary is period-wide; print uses report.transactions after filtering.',
    'WARN',false
  FROM relations

  UNION ALL
  SELECT 'REPO_CLASSIFICATION_AND_WRITER_GAPS','Every transaction type has a known writer and displayed signed side',
    'Repository: voucher_adjustment_expense debit omitted in inherited v1 JSON; no protected opening_seed or adjustment_credit/debit writer found; Chakkar net formula does not prevent negative net; withdrawal RPC currently permits operator.',
    'WARN',false
  FROM relations

  UNION ALL
  SELECT 'REPO_DATE_FILTER_AND_PRINT','Monthly close uses the whole calendar month independently of custom display filters',
    'Current statement intersects p_date_from/p_date_to with month bounds and recomputes opening at effective period_start; type/search filters affect displayed rows; print consumes report.transactions.',
    'WARN',false
  FROM relations

  UNION ALL
  SELECT 'REPO_REVERSAL_SEMANTICS','Reversal history expectations are explicit for each source',
    'Commission reversals append signed rows; Chakkar and Owner/Gari withdrawal reversal paths delete their linked rows (withdrawal also deletes Cashbook history).',
    'WARN',false
  FROM relations
),
final_rows AS (
  SELECT check_name,expected,actual,result FROM checks
  UNION ALL
  SELECT 'PHASE_6_PREFLIGHT_OVERALL',
    'All mandatory Owner/Gari monthly closing contracts pass',
    'mandatory failures='||(count(*) FILTER (WHERE is_mandatory AND result<>'PASS'))::text
      ||'; advisory warnings='||(count(*) FILTER (WHERE NOT is_mandatory AND result='WARN'))::text,
    CASE WHEN count(*) FILTER (WHERE is_mandatory AND result='FAIL')>0 THEN 'FAIL'
      WHEN count(*) FILTER (WHERE NOT is_mandatory AND result='WARN')>0 THEN 'WARN'
      ELSE 'PASS' END
  FROM checks
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='PHASE_6_PREFLIGHT_OVERALL' THEN 1 ELSE 0 END,check_name;
