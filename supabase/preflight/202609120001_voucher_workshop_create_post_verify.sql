-- READ ONLY
with
rpc as (
  select p.oid,pg_get_functiondef(p.oid) definition,
    regexp_replace(lower(pg_get_functiondef(p.oid)),'[[:space:]]+','','g') normalized_definition,
    p.prosecdef,p.proconfig
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='create_voucher_workshop_entry'
),
checks as (
  select 'CREATE_RPC_EXISTS'::text check_name,
    case when count(*)=1 then 'PASS' else 'FAIL' end status,
    format('%s create_voucher_workshop_entry function(s) found.',count(*)) details,true blocking
  from rpc
  union all
  select 'ORIGIN_COLUMNS',
    case when exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='workshop_entries' and column_name='created_from_voucher_id'
    ) and exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='voucher_workshop_entries' and column_name='link_origin'
    ) then 'PASS' else 'FAIL' end,
    'Origin tracking columns exist.',true
  union all
  select 'ATOMIC_COMPONENTS_PRESENT',
    case when count(*)=1 and bool_and(
      normalized_definition like '%insertintopublic.workshop_entries%'
      and normalized_definition like '%insertintopublic.workshop_entry_items%'
      and normalized_definition like '%insertintopublic.expense_items%'
      and normalized_definition like '%insertintopublic.voucher_workshop_entries%'
      and normalized_definition like '%insertintopublic.cashbook_entries%'
      and normalized_definition like '%performpublic.ut_sync_voucher_cashbook%'
    ) then 'PASS' else 'FAIL' end,
    'Create RPC contains Workshop source/items, Voucher item/link and Cashbook reconciliation.',true
  from rpc
  union all
  select 'VOUCHER_CONTEXT_SCOPED',
    case when count(*)=1 and bool_and(
      normalized_definition like '%public.ut_resolve_voucher_context(p_voucher_id)%'
      and normalized_definition like '%voucher_context.context_adda_id%'
      and normalized_definition like '%voucher_context.context_vehicle_id%'
    ) then 'PASS' else 'FAIL' end,
    'Authoritative Voucher Adda/Vehicle context is used.',true
  from rpc
  union all
  select 'FINALIZED_VOUCHER_PROTECTED',
    case when count(*)=1 and bool_and(
      normalized_definition like '%public.vehicle_chakkar_settlements%'
      and normalized_definition like '%finalized_voucher_is_read_only%'
    ) then 'PASS' else 'FAIL' end,
    'Finalized Voucher is protected.',true
  from rpc
  union all
  select 'CREATED_LINK_DETACH_PROTECTED',
    case when exists (
      select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='sync_voucher_workshop_entries'
        and regexp_replace(lower(pg_get_functiondef(p.oid)),'[[:space:]]+','','g')
          like '%voucher_created_workshop_requires_reversal%'
    ) then 'PASS' else 'FAIL' end,
    'Voucher-created Workshop cannot be silently detached.',true
),
summary as (
  select count(*) filter(where blocking and status='FAIL')::int blocking_failures,
    count(*) filter(where status='PASS')::int passed,
    count(*) filter(where status='INFO')::int informational
  from checks
),
output_rows as (
  select 0 sort_order,'OVERALL_VOUCHER_WORKSHOP_CREATE_POST_VERIFY'::text check_name,
    case when blocking_failures=0 then 'PASS' else 'FAIL' end status,
    format('%s blocking check(s) failed; %s passed; %s informational.',
      blocking_failures,passed,informational) details
  from summary
  union all
  select 1,check_name,status,details from checks
)
select check_name,status,details from output_rows
order by sort_order,check_name;
