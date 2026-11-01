with
function_defs as (
  select
    p.oid,
    n.nspname,
    p.proname,
    pg_get_function_identity_arguments(p.oid) identity_args,
    pg_get_functiondef(p.oid) definition,
    p.prosecdef,
    p.proconfig
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname in (
      'create_voucher_oil_entry',
      'sync_voucher_oil_entries',
      'save_oil_vehicle_entry',
      'delete_oil_vehicle_entry',
      'ut_sync_voucher_cashbook'
    )
),
integrity as (
  select
    count(*) filter (
      where ove.created_from_voucher_id is not null
        and not exists (
          select 1 from public.expenses e
          where e.id=ove.created_from_voucher_id
        )
    )::bigint as orphan_created_from_voucher,
    count(*) filter (
      where voe.link_origin='voucher_created'
        and (
          ove.created_from_voucher_id is distinct from voe.voucher_id
          or ove.id is null
        )
    )::bigint as voucher_created_origin_mismatch,
    count(*) filter (
      where voe.link_origin not in ('existing_link','voucher_created')
    )::bigint as invalid_link_origin
  from public.voucher_oil_entries voe
  left join public.oil_vehicle_entries ove
    on ove.id=voe.oil_vehicle_entry_id
),
duplicates as (
  select
    (
      select count(*) from (
        select created_from_voucher_id
        from public.oil_vehicle_entries
        where created_from_voucher_id is not null
        group by created_from_voucher_id
        having count(*)>1
      ) x
    )::bigint as duplicate_created_sources,
    (
      select count(*) from (
        select voucher_id
        from public.voucher_oil_entries
        where link_origin='voucher_created'
        group by voucher_id
        having count(*)>1
      ) x
    )::bigint as duplicate_voucher_created_links
),
amount_integrity as (
  select
    count(*) filter (
      where item_count<>1
         or item_total is distinct from source_total
    )::bigint as voucher_created_amount_mismatch
  from (
    select
      voe.voucher_id,
      coalesce(sum(ove.total_amount),0) source_total,
      (
        select count(*)
        from public.expense_items ei
        where ei.expense_id=voe.voucher_id
          and ei.expense_type='Oil / Lubricants'
          and ei.expense_class='vehicle_periodic'
      ) item_count,
      (
        select coalesce(sum(ei.amount),0)
        from public.expense_items ei
        where ei.expense_id=voe.voucher_id
          and ei.expense_type='Oil / Lubricants'
          and ei.expense_class='vehicle_periodic'
      ) item_total
    from public.voucher_oil_entries voe
    join public.oil_vehicle_entries ove
      on ove.id=voe.oil_vehicle_entry_id
    where voe.link_origin='voucher_created'
    group by voe.voucher_id
  ) q
),
context_integrity as (
  select count(*)::bigint as context_mismatch_count
  from public.voucher_oil_entries voe
  join public.oil_vehicle_entries ove
    on ove.id=voe.oil_vehicle_entry_id
  left join lateral public.ut_resolve_voucher_context(voe.voucher_id) ctx on true
  where ctx.context_adda_id is null
     or ctx.context_vehicle_id is null
     or ove.adda_id is distinct from ctx.context_adda_id
     or ove.vehicle_id is distinct from ctx.context_vehicle_id
),
finalized_integrity as (
  select count(*)::bigint as finalized_oil_mismatch_count
  from public.vehicle_chakkar_settlements vcs
  join public.voucher_oil_entries voe on voe.voucher_id=vcs.voucher_id
  join public.oil_vehicle_entries ove on ove.id=voe.oil_vehicle_entry_id
  where ove.adda_id is distinct from vcs.adda_id
     or ove.vehicle_id is distinct from vcs.vehicle_id
     or exists (
       select 1
       from public.expense_items ei
       where ei.expense_id=vcs.voucher_id
         and ei.expense_type='Oil / Lubricants'
         and (
           ei.expense_class is distinct from 'vehicle_periodic'
           or ei.amount is distinct from (
             select coalesce(sum(ove2.total_amount),0)
             from public.voucher_oil_entries voe2
             join public.oil_vehicle_entries ove2
               on ove2.id=voe2.oil_vehicle_entry_id
             where voe2.voucher_id=vcs.voucher_id
           )
         )
     )
),
cashbook_integrity as (
  select
    (
      select count(*) from (
        select reference_id
        from public.cashbook_entries
        where reference_type='oil_supplier_payment'
        group by reference_id
        having count(*)>1
      ) x
    )::bigint as duplicate_supplier_payment_cashbook,
    (
      select count(*)
      from public.cashbook_entries cb
      join public.oil_supplier_payments osp
        on cb.reference_type='oil_supplier_payment'
       and cb.reference_id=osp.id::text
      where cb.amount is distinct from osp.payment_now
    )::bigint as supplier_payment_amount_mismatch
),
checks as (
  select
    'NEW_COLUMNS'::text check_name,
    case when
      exists (
        select 1 from information_schema.columns
        where table_schema='public'
          and table_name='oil_vehicle_entries'
          and column_name='created_from_voucher_id'
          and data_type='bigint'
      )
      and exists (
        select 1 from information_schema.columns
        where table_schema='public'
          and table_name='voucher_oil_entries'
          and column_name='link_origin'
          and data_type='text'
      )
    then 'PASS' else 'FAIL' end status,
    'created_from_voucher_id and link_origin exist with expected base types.' details,
    true blocking

  union all
  select
    'ORIGIN_CONSTRAINT',
    case when exists (
      select 1
      from pg_constraint c
      join pg_class t on t.oid=c.conrelid
      join pg_namespace n on n.oid=t.relnamespace
      where n.nspname='public'
        and t.relname='voucher_oil_entries'
        and c.contype='c'
        and pg_get_constraintdef(c.oid) ilike '%existing_link%'
        and pg_get_constraintdef(c.oid) ilike '%voucher_created%'
    ) then 'PASS' else 'FAIL' end,
    'voucher_oil_entries.link_origin is constrained to the two supported origins.',
    true

  union all
  select
    'CREATE_RPC_EXISTS',
    case when exists (
      select 1
      from function_defs
      where proname='create_voucher_oil_entry'
        and identity_args='p_voucher_id bigint, p_entry_date date, p_source_type text, p_oil_shop_id uuid, p_oil_product_id uuid, p_liters numeric, p_rate_per_liter numeric, p_bill_no text, p_odometer bigint, p_next_oil_change_date date, p_oil_remarks text, p_payment_method text, p_voucher_item_remarks text'
    ) then 'PASS' else 'FAIL' end,
    'Exact create_voucher_oil_entry RPC signature is deployed.',
    true

  union all
  select
    'SYNC_RPC_HARDENED_FINALIZED',
    case when exists (
      select 1
      from function_defs
      where proname='sync_voucher_oil_entries'
        and definition ilike '%FINALIZED_VOUCHER_IS_READ_ONLY%'
        and definition ilike '%vehicle_chakkar_settlements%'
    ) then 'PASS' else 'FAIL' end,
    'sync_voucher_oil_entries independently rejects finalized Vouchers.',
    true

  union all
  select
    'SYNC_RPC_PROTECTS_CREATED_LINK',
    case when exists (
      select 1
      from function_defs
      where proname='sync_voucher_oil_entries'
        and definition ilike '%VOUCHER_CREATED_OIL_LINK_CANNOT_BE_DETACHED%'
        and definition ilike '%link_origin%'
    ) then 'PASS' else 'FAIL' end,
    'Ordinary existing-link synchronization cannot silently detach a voucher-created Oil source.',
    true

  union all
  select
    'CREATE_RPC_EXACT_ONCE',
    case when exists (
      select 1
      from function_defs
      where proname='create_voucher_oil_entry'
        and definition ilike '%Oil / Lubricants%'
        and definition ilike '%vehicle_periodic%'
        and definition ilike '%ut_sync_voucher_cashbook%'
        and definition not ilike '%insert into public.oil_supplier_payments%'
        and definition not ilike '%update public.oil_supplier_payments%'
        and definition not ilike '%delete from public.oil_supplier_payments%'
    ) then 'PASS' else 'FAIL' end,
    'Create RPC creates the Oil Voucher item and resynchronizes Voucher Cashbook without directly creating, updating, or deleting supplier payment rows.',
    true

  union all
  select
    'CREATE_RPC_SOURCE_MODES',
    case when exists (
      select 1
      from function_defs
      where proname='create_voucher_oil_entry'
        and definition ilike '%external_shop%'
        and definition ilike '%adda_stock%'
        and definition ilike '%INSUFFICIENT_OIL_STOCK%'
    ) then 'PASS' else 'FAIL' end,
    'Create RPC contains both external-shop and Adda-stock validation paths.',
    true

  union all
  select
    'VOUCHER_CREATED_SOURCE_IMMUTABILITY',
    case when
      exists (
        select 1
        from function_defs
        where proname='save_oil_vehicle_entry'
          and definition ilike '%VOUCHER_CREATED_OIL_ENTRY_IS_READ_ONLY%'
      )
      and exists (
        select 1
        from function_defs
        where proname='delete_oil_vehicle_entry'
          and definition ilike '%VOUCHER_CREATED_OIL_ENTRY_IS_READ_ONLY%'
      )
    then 'PASS' else 'FAIL' end,
    'Ordinary Oil edit/delete RPCs fail closed for Voucher-created sources.',
    true

  union all
  select
    'ORIGIN_DATA_INTEGRITY',
    case when
      orphan_created_from_voucher=0
      and voucher_created_origin_mismatch=0
      and invalid_link_origin=0
    then 'PASS' else 'FAIL' end,
    format(
      'orphan_created_from_voucher=%s, voucher_created_origin_mismatch=%s, invalid_link_origin=%s',
      orphan_created_from_voucher,
      voucher_created_origin_mismatch,
      invalid_link_origin
    ),
    true
  from integrity

  union all
  select
    'VOUCHER_CREATED_UNIQUENESS',
    case when duplicate_created_sources=0
          and duplicate_voucher_created_links=0
      then 'PASS' else 'FAIL' end,
    format(
      'duplicate_created_sources=%s, duplicate_voucher_created_links=%s',
      duplicate_created_sources,
      duplicate_voucher_created_links
    ),
    true
  from duplicates

  union all
  select
    'VOUCHER_CREATED_AMOUNT_RECONCILIATION',
    case when voucher_created_amount_mismatch=0
      then 'PASS' else 'FAIL' end,
    format(
      '%s voucher-created Oil Voucher(s) have item/source amount mismatch.',
      voucher_created_amount_mismatch
    ),
    true
  from amount_integrity

  union all
  select
    'VOUCHER_OIL_CONTEXT_INTEGRITY',
    case when context_mismatch_count=0
      then 'PASS' else 'FAIL' end,
    format(
      '%s Voucher/Oil link(s) disagree with authoritative Voucher Adda/Vehicle context.',
      context_mismatch_count
    ),
    true
  from context_integrity

  union all
  select
    'FINALIZED_VOUCHER_OIL_INTEGRITY',
    case when finalized_oil_mismatch_count=0
      then 'PASS' else 'FAIL' end,
    format(
      '%s finalized Voucher(s) have Oil context/amount inconsistency.',
      finalized_oil_mismatch_count
    ),
    true
  from finalized_integrity

  union all
  select
    'OIL_SUPPLIER_CASHBOOK_EXACT_ONCE',
    case when duplicate_supplier_payment_cashbook=0
           and supplier_payment_amount_mismatch=0
      then 'PASS' else 'FAIL' end,
    format(
      'duplicate_supplier_payment_cashbook=%s, supplier_payment_amount_mismatch=%s',
      duplicate_supplier_payment_cashbook,
      supplier_payment_amount_mismatch
    ),
    true
  from cashbook_integrity

  union all
  select
    'RLS_STATUS',
    case when bool_and(c.relrowsecurity)
      then 'PASS' else 'FAIL' end,
    'RLS remains enabled on Oil source/link/accounting tables.',
    true
  from pg_class c
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public'
    and c.relname in (
      'oil_shops',
      'oil_products',
      'oil_vehicle_entries',
      'oil_stock_movements',
      'oil_supplier_bills',
      'oil_supplier_payments',
      'oil_supplier_payment_allocations',
      'voucher_oil_entries'
    )

  union all
  select
    'MIGRATION_HISTORY',
    'INFO',
    case
      when to_regclass('supabase_migrations.schema_migrations') is null
        then 'Migration history table is unavailable.'
      when exists (
        select 1
        from supabase_migrations.schema_migrations
        where version='202609130002'
      )
        then 'Version 202609130002 is recorded in migration history.'
      else 'Version 202609130002 is not recorded; expected if SQL was applied manually.'
    end,
    false
),
summary as (
  select
    count(*) filter(where blocking and status='FAIL')::int blocking_failures,
    count(*) filter(where status='PASS')::int passed,
    count(*) filter(where status='INFO')::int informational
  from checks
),
output_rows as (
  select
    0 as sort_order,
    'OVERALL_VOUCHER_OIL_CREATE_POST_VERIFY'::text check_name,
    case when blocking_failures=0 then 'PASS' else 'FAIL' end status,
    format(
      '%s blocking check(s) failed; %s passed; %s informational.',
      blocking_failures,passed,informational
    ) details,
    true blocking
  from summary

  union all

  select
    1 as sort_order,
    check_name,
    status,
    details,
    blocking
  from checks
)
select
  check_name,
  status,
  details,
  blocking
from output_rows
order by sort_order,check_name;