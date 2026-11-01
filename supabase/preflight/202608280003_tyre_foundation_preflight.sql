-- UT Software — Tyre Foundation Phase 1 deployment preflight
-- STRICTLY READ ONLY: catalog inspection and SELECT queries only.
-- This file performs no DDL, DML, grants, RPC calls, or database mutations.

with
planned_relations(object_name) as (
  values
    ('tyre_shops'),
    ('tyre_products'),
    ('tyre_assets'),
    ('vehicle_tyre_positions'),
    ('tyre_vehicle_entries'),
    ('tyre_vehicle_entry_items'),
    ('tyre_fitments'),
    ('tyre_asset_events')
),
planned_types(object_name) as (
  values
    ('tyre_shop_type'),
    ('tyre_source_type'),
    ('tyre_product_type'),
    ('tyre_asset_status'),
    ('tyre_event_type'),
    ('tyre_position_side'),
    ('tyre_work_type')
),
planned_functions(object_name) as (
  values
    ('normalize_tyre_serial'),
    ('save_tyre_shop'),
    ('save_tyre_product'),
    ('save_tyre_asset'),
    ('save_vehicle_tyre_position'),
    ('save_vehicle_tyre_entry'),
    ('delete_vehicle_tyre_entry')
),
checks(check_name,status,details,blocking) as (
  values
    (
      'REQUIRED_BASE_TABLES',
      case when to_regclass('public.addas') is not null
                  and to_regclass('public.vehicles') is not null
                  and to_regclass('public.profiles') is not null
                  and to_regclass('public.expense_items') is not null
           then 'PASS' else 'FAIL' end,
      'Required tables: public.addas, public.vehicles, public.profiles and public.expense_items.',
      true
    ),
    (
      'ADDAS_ID_UUID',
      case when exists (
        select 1 from information_schema.columns
        where table_schema='public' and table_name='addas' and column_name='id'
          and data_type='uuid' and is_nullable='NO'
      ) then 'PASS' else 'FAIL' end,
      coalesce((select format('public.addas.id: type=%s, nullable=%s',data_type,is_nullable)
                from information_schema.columns
                where table_schema='public' and table_name='addas' and column_name='id'),
               'public.addas.id is missing.'),
      true
    ),
    (
      'VEHICLES_REQUIRED_COLUMN_TYPES',
      case when exists (
        select 1 from information_schema.columns
        where table_schema='public' and table_name='vehicles' and column_name='id'
          and data_type='uuid' and is_nullable='NO'
      ) and exists (
        select 1 from information_schema.columns
        where table_schema='public' and table_name='vehicles' and column_name='adda_id'
          and data_type='uuid' and is_nullable='NO'
      ) and exists (
        select 1 from information_schema.columns
        where table_schema='public' and table_name='vehicles' and column_name='vehicle_no'
          and data_type='text'
      ) then 'PASS' else 'FAIL' end,
      'Expected public.vehicles.id uuid NOT NULL, adda_id uuid NOT NULL and vehicle_no text.',
      true
    ),
    (
      'ADDAS_PRIMARY_KEY',
      case when exists (
        select 1
        from information_schema.table_constraints tc
        join information_schema.key_column_usage kcu
          on kcu.constraint_schema=tc.constraint_schema
         and kcu.constraint_name=tc.constraint_name
         and kcu.table_schema=tc.table_schema
         and kcu.table_name=tc.table_name
        where tc.table_schema='public' and tc.table_name='addas'
          and tc.constraint_type='PRIMARY KEY' and kcu.column_name='id'
      ) then 'PASS' else 'FAIL' end,
      'public.addas.id must be the primary key.',
      true
    ),
    (
      'VEHICLES_PRIMARY_KEY',
      case when exists (
        select 1
        from information_schema.table_constraints tc
        join information_schema.key_column_usage kcu
          on kcu.constraint_schema=tc.constraint_schema
         and kcu.constraint_name=tc.constraint_name
         and kcu.table_schema=tc.table_schema
         and kcu.table_name=tc.table_name
        where tc.table_schema='public' and tc.table_name='vehicles'
          and tc.constraint_type='PRIMARY KEY' and kcu.column_name='id'
      ) then 'PASS' else 'FAIL' end,
      'public.vehicles.id must be the primary key.',
      true
    ),
    (
      'VEHICLES_ADDA_FOREIGN_KEY',
      case when exists (
        select 1
        from information_schema.table_constraints tc
        join information_schema.key_column_usage kcu
          on kcu.constraint_schema=tc.constraint_schema
         and kcu.constraint_name=tc.constraint_name
         and kcu.table_schema=tc.table_schema
         and kcu.table_name=tc.table_name
        join information_schema.constraint_column_usage ccu
          on ccu.constraint_schema=tc.constraint_schema
         and ccu.constraint_name=tc.constraint_name
        where tc.table_schema='public' and tc.table_name='vehicles'
          and tc.constraint_type='FOREIGN KEY'
          and kcu.column_name='adda_id'
          and ccu.table_schema='public' and ccu.table_name='addas' and ccu.column_name='id'
      ) then 'PASS' else 'FAIL' end,
      'Semantic FK required: public.vehicles.adda_id -> public.addas.id. Constraint name and delete action are not assumed.',
      true
    ),
    (
      'VEHICLE_ADDA_DATA_INTEGRITY',
      case when not exists (
        select 1 from public.vehicles vehicle
        left join public.addas adda on adda.id=vehicle.adda_id
        where vehicle.adda_id is null or adda.id is null
      ) then 'PASS' else 'FAIL' end,
      (select format('%s vehicle row(s) have NULL or invalid adda_id.',count(*))
       from public.vehicles vehicle
       left join public.addas adda on adda.id=vehicle.adda_id
       where vehicle.adda_id is null or adda.id is null),
      true
    ),
    (
      'TENANT_HELPER_SIGNATURES',
      case when to_regprocedure('public.current_user_adda_id()') is not null
                  and to_regprocedure('public.current_user_role()') is not null
                  and to_regprocedure('public.is_super_admin()') is not null
           then 'PASS' else 'FAIL' end,
      'Required helpers: current_user_adda_id(), current_user_role(), is_super_admin().',
      true
    ),
    (
      'TENANT_HELPER_RETURN_TYPES',
      case when coalesce((select pg_get_function_result(to_regprocedure('public.current_user_adda_id()'))),'')='uuid'
                  and coalesce((select pg_get_function_result(to_regprocedure('public.current_user_role()'))),'')='text'
                  and coalesce((select pg_get_function_result(to_regprocedure('public.is_super_admin()'))),'')='boolean'
           then 'PASS' else 'FAIL' end,
      format('current_user_adda_id=%s; current_user_role=%s; is_super_admin=%s',
        coalesce((select pg_get_function_result(to_regprocedure('public.current_user_adda_id()'))),'missing'),
        coalesce((select pg_get_function_result(to_regprocedure('public.current_user_role()'))),'missing'),
        coalesce((select pg_get_function_result(to_regprocedure('public.is_super_admin()'))),'missing')),
      true
    ),
    (
      'TENANT_HELPER_SECURITY',
      case when not exists (
        select 1
        from pg_proc procedure
        where procedure.oid in (
          to_regprocedure('public.current_user_adda_id()'),
          to_regprocedure('public.current_user_role()'),
          to_regprocedure('public.is_super_admin()')
        )
        and (
          not procedure.prosecdef
          or coalesce(array_to_string(procedure.proconfig,','),'') !~ 'search_path=(pg_catalog, public|public, pg_temp)'
        )
      ) and (
        select count(*) from pg_proc procedure
        where procedure.oid in (
          to_regprocedure('public.current_user_adda_id()'),
          to_regprocedure('public.current_user_role()'),
          to_regprocedure('public.is_super_admin()')
        )
      )=3 then 'PASS' else 'FAIL' end,
      'All tenant helpers must be SECURITY DEFINER with the deployed locked pg_catalog, public search_path (public, pg_temp is also accepted).',
      true
    ),
    (
      'AUTHENTICATED_ROLE_EXISTS',
      case when exists(select 1 from pg_roles where rolname='authenticated') then 'PASS' else 'FAIL' end,
      'Supabase authenticated database role must exist.',
      true
    ),
    (
      'UUID_GENERATION_AVAILABLE',
      case when to_regprocedure('gen_random_uuid()') is not null then 'PASS' else 'FAIL' end,
      case when to_regprocedure('gen_random_uuid()') is not null
           then format('gen_random_uuid() is available; pgcrypto installed=%s.',exists(select 1 from pg_extension where extname='pgcrypto'))
           else 'gen_random_uuid() is unavailable.' end,
      true
    ),
    (
      'TEXT_NORMALIZATION_PRIMITIVES',
      case when to_regprocedure('btrim(text)') is not null and to_regprocedure('lower(text)') is not null
           then 'PASS' else 'FAIL' end,
      'Serial contract will preserve serial_number and compare lower(btrim(serial_number)); internal whitespace and manufacturer punctuation remain meaningful.',
      true
    ),
    (
      'PLANNED_RELATION_NAMES_AVAILABLE',
      case when not exists (
        select 1
        from planned_relations planned
        join pg_class object on object.relname=planned.object_name
        join pg_namespace namespace on namespace.oid=object.relnamespace and namespace.nspname='public'
      ) then 'PASS' else 'FAIL' end,
      coalesce((
        select 'Conflicting public relation(s): '||string_agg(planned.object_name,', ' order by planned.object_name)
        from planned_relations planned
        join pg_class object on object.relname=planned.object_name
        join pg_namespace namespace on namespace.oid=object.relnamespace and namespace.nspname='public'
      ),'All planned Tyre relation names are available.'),
      true
    ),
    (
      'PLANNED_TYPE_NAMES_AVAILABLE',
      case when not exists (
        select 1
        from planned_types planned
        join pg_type object on object.typname=planned.object_name
        join pg_namespace namespace on namespace.oid=object.typnamespace and namespace.nspname='public'
      ) then 'PASS' else 'FAIL' end,
      coalesce((
        select 'Conflicting public type(s): '||string_agg(planned.object_name,', ' order by planned.object_name)
        from planned_types planned
        join pg_type object on object.typname=planned.object_name
        join pg_namespace namespace on namespace.oid=object.typnamespace and namespace.nspname='public'
      ),'No planned Tyre enum/type name conflicts exist.'),
      true
    ),
    (
      'PLANNED_FUNCTION_NAMES_AVAILABLE',
      case when not exists (
        select 1
        from planned_functions planned
        join pg_proc procedure on procedure.proname=planned.object_name
        join pg_namespace namespace on namespace.oid=procedure.pronamespace and namespace.nspname='public'
      ) then 'PASS' else 'FAIL' end,
      coalesce((
        select 'Conflicting public function name(s): '||string_agg(distinct planned.object_name,', ' order by planned.object_name)
        from planned_functions planned
        join pg_proc procedure on procedure.proname=planned.object_name
        join pg_namespace namespace on namespace.oid=procedure.pronamespace and namespace.nspname='public'
      ),'No planned Tyre function-name conflicts exist.'),
      true
    ),
    (
      'UNEXPECTED_TYRE_SCHEMA_OBJECTS',
      case when not exists (
        select 1
        from pg_class object
        join pg_namespace namespace on namespace.oid=object.relnamespace
        where namespace.nspname='public'
          and (object.relname like 'tyre_%' or object.relname like '%_tyre_%')
      ) then 'PASS' else 'FAIL' end,
      coalesce((
        select 'Existing Tyre-like relation(s) require reconciliation: '||string_agg(object.relname,', ' order by object.relname)
        from pg_class object
        join pg_namespace namespace on namespace.oid=object.relnamespace
        where namespace.nspname='public'
          and (object.relname like 'tyre_%' or object.relname like '%_tyre_%')
      ),'No existing Tyre-like public relations were found.'),
      true
    ),
    (
      'VEHICLES_RLS_ENABLED',
      case when coalesce((
        select object.relrowsecurity
        from pg_class object
        join pg_namespace namespace on namespace.oid=object.relnamespace
        where namespace.nspname='public' and object.relname='vehicles' and object.relkind in ('r','p')
      ),false) then 'INFO' else 'INFO' end,
      case when coalesce((select object.relrowsecurity from pg_class object join pg_namespace namespace on namespace.oid=object.relnamespace where namespace.nspname='public' and object.relname='vehicles' and object.relkind in ('r','p')),false)
           then 'Existing public.vehicles RLS is enabled; Phase 1 Tyre tables must add their own tenant RLS.'
           else 'Existing public.vehicles RLS is disabled; this is documented, not changed by Tyre Phase 1. Tyre RPCs must independently validate Vehicle Adda ownership.' end,
      false
    ),
    (
      'VEHICLES_AUTHENTICATED_POLICY_PRESENT',
      case when exists (
        select 1 from pg_policies
        where schemaname='public' and tablename='vehicles'
          and ('authenticated'=any(roles) or 'public'=any(roles))
          and cmd in ('SELECT','ALL')
      ) then 'INFO' else 'INFO' end,
      case when exists (select 1 from pg_policies where schemaname='public' and tablename='vehicles' and ('authenticated'=any(roles) or 'public'=any(roles)) and cmd in ('SELECT','ALL'))
           then 'An existing authenticated Vehicle read policy is present.'
           else 'No authenticated Vehicle read policy is present. Phase 1 will not change Vehicle security; Tyre writes must validate Vehicle Adda in SECURITY DEFINER RPCs.' end,
      false
    ),
    (
      'EXPENSE_CLASS_COLUMN',
      case when exists (
        select 1 from information_schema.columns
        where table_schema='public' and table_name='expense_items'
          and column_name='expense_class' and data_type='text'
          and is_nullable='NO' and column_default like '%regular_trip%'
      ) then 'PASS' else 'FAIL' end,
      'Voucher classification requires expense_items.expense_class text NOT NULL with legacy regular_trip default.',
      true
    ),
    (
      'VEHICLE_PERIODIC_CLASS_ALLOWED',
      case when exists (
        select 1
        from pg_constraint constraint_row
        join pg_class table_row on table_row.oid=constraint_row.conrelid
        join pg_namespace namespace on namespace.oid=table_row.relnamespace
        where namespace.nspname='public' and table_row.relname='expense_items'
          and constraint_row.contype='c'
          and pg_get_constraintdef(constraint_row.oid) like '%expense_class%'
          and pg_get_constraintdef(constraint_row.oid) like '%vehicle_periodic%'
          and pg_get_constraintdef(constraint_row.oid) like '%regular_trip%'
      ) then 'PASS' else 'FAIL' end,
      'Existing Voucher expense_class constraint must permit regular_trip and vehicle_periodic; Tyre will use vehicle_periodic later.',
      true
    ),
    (
      'EXISTING_TYRE_VOUCHER_ROWS',
      'INFO',
      (select format('%s existing expense_item row(s) use expense_type Tyre; Phase 1 will not alter or migrate them.',count(*))
       from public.expense_items where lower(btrim(coalesce(expense_type,'')))='tyre'),
      false
    ),
    (
      'MIGRATION_HISTORY_TABLE',
      case when to_regclass('supabase_migrations.schema_migrations') is not null then 'INFO' else 'INFO' end,
      case when to_regclass('supabase_migrations.schema_migrations') is not null
           then 'supabase_migrations.schema_migrations exists; confirm version 202608280003 remains pending before deployment.'
           else 'Supabase migration-history table is not visible to this SQL role; history must be checked separately.' end,
      false
    ),
    (
      'SERIAL_UNIQUENESS_DESIGN',
      'INFO',
      'Planned uniqueness: UNIQUE(adda_id, lower(btrim(serial_number))). Original serial is preserved; punctuation and internal whitespace are not removed.',
      false
    ),
    (
      'FITMENT_CONCURRENCY_DESIGN',
      'INFO',
      'Phase 1 migration must add partial uniqueness for one open fitment per tyre asset and one open tyre per vehicle position.',
      false
    ),
    (
      'PHASE_1_ACCOUNTING_BOUNDARY',
      'INFO',
      'Phase 1 must not create Tyre payments, Voucher links, external sales, Cashbook rows, or profitability effects.',
      false
    )
),
combined as (
  select
    'OVERALL_TYRE_FOUNDATION_PREFLIGHT'::text as check_name,
    case when count(*) filter(where blocking and status='FAIL')=0 then 'PASS' else 'FAIL' end as status,
    format(
      '%s blocking check(s) failed; %s passed; %s informational',
      count(*) filter(where blocking and status='FAIL'),
      count(*) filter(where status='PASS'),
      count(*) filter(where status='INFO')
    ) as details
  from checks
  union all
  select check_name,status,details from checks
)
select check_name,status,details
from combined
order by
  case when check_name='OVERALL_TYRE_FOUNDATION_PREFLIGHT' then 0 else 1 end,
  check_name;
