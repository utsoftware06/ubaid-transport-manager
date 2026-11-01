
--
-- Purpose:
--   Confirm that a completed Bilty Movement Group can safely obtain one real,
--   persisted Loading for its authoritative Outbound Bilty.  The bridge is
--   invoked explicitly by the Voucher UI; this preflight creates nothing.
--
-- Safety boundaries:
--   * loadings.booking_id = bookings.id is the only relationship used.
--   * Existing NULL-booking legacy Loadings are not inferred or changed.
--   * The proposed Loading starts with advance_amount = 0, so the existing
--     Loading advance synchronizer must not create Cashbook movement.
--   * No Bilty, Movement Group, Voucher, Diesel, or accounting row is changed.

with
required_relations(relation_name) as (
  values
    ('public.addas'),
    ('public.profiles'),
    ('public.vehicles'),
    ('public.bookings'),
    ('public.bilty_movement_groups'),
    ('public.loadings'),
    ('public.diesel_entries'),
    ('public.vehicle_chakkar_settlements'),
    ('public.cashbook_entries')
),
missing_relations as (
  select required.relation_name
  from required_relations required
  where to_regclass(required.relation_name) is null
),
-- For Loading columns explicitly supplied by the bridge, nullability is intentionally
-- not hard-coded here. Their TYPE is still enforced; insert safety is separately
-- enforced by bridge_supplied_loading_columns + LOADINGS_INSERT_DEFAULT_CONTRACT.
required_columns(table_name, column_name, allowed_udt_names, required_nullable) as (
  values
    ('bilty_movement_groups', 'id', array['uuid']::text[], 'NO'),
    ('bilty_movement_groups', 'adda_id', array['uuid']::text[], 'NO'),
    ('bilty_movement_groups', 'outbound_bilty_id', array['uuid']::text[], 'NO'),
    ('bilty_movement_groups', 'status', array['text', 'varchar']::text[], null::text),
    ('bookings', 'id', array['uuid']::text[], 'NO'),
    ('bookings', 'adda_id', array['uuid']::text[], null::text),
    ('bookings', 'booking_no', array['text', 'varchar']::text[], null::text),
    ('bookings', 'booking_date', array['date']::text[], null::text),
    ('bookings', 'loading_date', array['date']::text[], null::text),
    ('bookings', 'trip_type', array['text', 'varchar']::text[], null::text),
    ('bookings', 'bilty_group_id', array['uuid']::text[], null::text),
    ('bookings', 'vehicle_id', array['uuid']::text[], null::text),
    ('bookings', 'from_city', array['text', 'varchar']::text[], null::text),
    ('bookings', 'to_city', array['text', 'varchar']::text[], null::text),
    ('bookings', 'freight', array['numeric']::text[], null::text),
    ('loadings', 'id', array['int8']::text[], 'NO'),
    ('loadings', 'loading_no', array['text', 'varchar']::text[], null::text),
    ('loadings', 'loading_date', array['date']::text[], null::text),
    ('loadings', 'booking_id', array['uuid']::text[], null::text),
    ('loadings', 'vehicle_id', array['uuid']::text[], null::text),
    ('loadings', 'driver_id', array['uuid']::text[], null::text),
    ('loadings', 'route', array['text', 'varchar']::text[], null::text),
    ('loadings', 'advance_amount', array['numeric']::text[], null::text),
    ('loadings', 'remaining_amount', array['numeric']::text[], null::text),
    ('loadings', 'payment_status', array['text', 'varchar']::text[], null::text),
    ('loadings', 'created_at', array['timestamp', 'timestamptz']::text[], null::text),
    ('vehicles', 'id', array['uuid']::text[], 'NO'),
    ('vehicles', 'adda_id', array['uuid']::text[], 'NO'),
    ('diesel_entries', 'loading_id', array['int8']::text[], null::text),
    ('diesel_entries', 'vehicle_id', array['uuid']::text[], 'NO'),
    ('diesel_entries', 'driver_id', array['uuid']::text[], 'YES'),
    ('cashbook_entries', 'reference_type', array['text', 'varchar']::text[], null::text),
    ('cashbook_entries', 'reference_id', array['text', 'varchar']::text[], null::text)
),
actual_columns as (
  select
    column_row.table_name,
    column_row.column_name,
    column_row.data_type,
    column_row.udt_name,
    column_row.is_nullable,
    column_row.column_default,
    column_row.is_identity,
    column_row.is_generated
  from information_schema.columns column_row
  where column_row.table_schema = 'public'
),
incompatible_columns as (
  select
    required.table_name,
    required.column_name,
    array_to_string(required.allowed_udt_names, '|') expected_type,
    required.required_nullable,
    actual.udt_name actual_type,
    actual.is_nullable actual_nullable
  from required_columns required
  left join actual_columns actual
    on actual.table_name = required.table_name
   and actual.column_name = required.column_name
  where actual.column_name is null
     or actual.udt_name <> all(required.allowed_udt_names)
     or (
       required.required_nullable is not null
       and actual.is_nullable <> required.required_nullable
     )
),
bridge_supplied_loading_columns(column_name, supplied_value) as (
  values
    ('loading_no', 'BILTY-<booking UUID>'),
    ('loading_date', 'COALESCE(bookings.loading_date, bookings.booking_date)'),
    ('booking_id', 'exact bookings.id'),
    ('vehicle_id', 'resolved Movement Group vehicle_id'),
    ('driver_id', 'NULL (no Driver is guessed)'),
    ('route', 'stored Bilty route or deterministic Bilty label'),
    ('advance_amount', '0'),
    ('remaining_amount', 'COALESCE(bookings.freight, 0)'),
    ('payment_status', 'Unpaid')
),
unsatisfied_implicit_loading_columns as (
  select
    column_row.column_name,
    column_row.udt_name,
    column_row.is_nullable,
    column_row.column_default,
    column_row.is_identity,
    column_row.is_generated
  from actual_columns column_row
  left join bridge_supplied_loading_columns supplied
    on supplied.column_name = column_row.column_name
  where column_row.table_name = 'loadings'
    and supplied.column_name is null
    and column_row.is_nullable = 'NO'
    and column_row.column_default is null
    and coalesce(column_row.is_identity, 'NO') <> 'YES'
    and coalesce(column_row.is_generated, 'NEVER') = 'NEVER'
),
loadings_column_contracts as (
  select
    column_row.column_name,
    column_row.data_type,
    column_row.udt_name,
    column_row.is_nullable,
    column_row.column_default,
    coalesce(supplied.supplied_value, 'not explicitly supplied') supplied_value,
    case
      when supplied.column_name is not null then 'YES_EXPLICIT_VALUE'
      when column_row.is_nullable = 'YES' then 'YES_NULL_ALLOWED'
      when column_row.column_default is not null
        or coalesce(column_row.is_identity, 'NO') = 'YES'
        or coalesce(column_row.is_generated, 'NEVER') <> 'NEVER'
        then 'YES_DATABASE_GENERATED'
      else 'NO_MISSING_VALUE_SOURCE'
    end bridge_insert_compatible
  from actual_columns column_row
  left join bridge_supplied_loading_columns supplied
    on supplied.column_name = column_row.column_name
  where column_row.table_name = 'loadings'
    and column_row.column_name in (
      'id', 'loading_no', 'loading_date', 'booking_id', 'vehicle_id',
      'driver_id', 'route', 'advance_amount', 'remaining_amount',
      'payment_status', 'created_at'
    )
),
loading_triggers as (
  select
    trigger_row.tgname,
    trigger_row.tgenabled,
    pg_get_triggerdef(trigger_row.oid) trigger_definition,
    pg_get_functiondef(trigger_row.tgfoid) trigger_function_definition
  from pg_trigger trigger_row
  where trigger_row.tgrelid = to_regclass('public.loadings')
    and not trigger_row.tgisinternal
),
advance_trigger_definition as (
  select lower(regexp_replace(trigger_row.trigger_function_definition, '[[:space:]]+', '', 'g')) normalized_definition
  from loading_triggers trigger_row
  where trigger_row.tgname = 'loadings_sync_advance_cashbook'
),
advance_sync_definition as (
  select lower(regexp_replace(pg_get_functiondef(procedure_row.oid), '[[:space:]]+', '', 'g')) normalized_definition
  from pg_proc procedure_row
  join pg_namespace namespace_row on namespace_row.oid = procedure_row.pronamespace
  where namespace_row.nspname = 'public'
    and procedure_row.proname = 'ut_sync_loading_advance_cashbook'
    and pg_get_function_identity_arguments(procedure_row.oid) = 'p_loading_id text'
),
eligible_completed_groups as (
  select movement.id
  from public.bilty_movement_groups movement
  join public.bookings outbound
    on outbound.id = movement.outbound_bilty_id
   and outbound.bilty_group_id = movement.id
   and outbound.trip_type = 'outbound'
  join public.vehicles vehicle
    on vehicle.id = outbound.vehicle_id
   and vehicle.adda_id = movement.adda_id
  where movement.status in ('completed', 'voucher_created')
    and (outbound.adda_id is null or outbound.adda_id = movement.adda_id)
    and 1 = (
      select count(*)
      from public.bookings member
      where member.bilty_group_id = movement.id
        and member.trip_type = 'outbound'
    )
    and 1 = (
      select count(*)
      from public.bookings member
      where member.bilty_group_id = movement.id
        and member.trip_type = 'return'
    )
    and not exists (
      select 1
      from public.bookings member
      where member.bilty_group_id = movement.id
        and (
          member.trip_type is null
          or member.trip_type not in ('outbound', 'local', 'return')
          or member.vehicle_id is distinct from outbound.vehicle_id
          or (
            member.adda_id is not null
            and member.adda_id is distinct from movement.adda_id
          )
        )
    )
),
zero_loading_groups as (
  select eligible.id
  from eligible_completed_groups eligible
  where not exists (
    select 1
    from public.bookings member
    join public.loadings loading on loading.booking_id = member.id
    where member.bilty_group_id = eligible.id
  )
),
member_loading_ambiguities as (
  select movement.id, member.id booking_id, count(loading.id) loading_count
  from eligible_completed_groups eligible
  join public.bilty_movement_groups movement on movement.id = eligible.id
  join public.bookings member on member.bilty_group_id = movement.id
  join public.loadings loading on loading.booking_id = member.id
  group by movement.id, member.id
  having count(loading.id) > 1
),
generated_loading_number_conflicts as (
  select movement.id movement_group_id, member.id booking_id, loading.id conflicting_loading_id
  from eligible_completed_groups eligible
  join public.bilty_movement_groups movement on movement.id = eligible.id
  join public.bookings member on member.bilty_group_id = movement.id
  join public.loadings loading on loading.loading_no = 'BILTY-' || member.id::text
  where loading.booking_id is distinct from member.id
),
group_loading_context_mismatches as (
  select distinct movement.id movement_group_id, loading.id loading_id
  from eligible_completed_groups eligible
  join public.bilty_movement_groups movement on movement.id = eligible.id
  join public.bookings member on member.bilty_group_id = movement.id
  join public.loadings loading on loading.booking_id = member.id
  left join public.vehicles vehicle on vehicle.id = loading.vehicle_id
  where loading.vehicle_id is distinct from member.vehicle_id
     or vehicle.adda_id is distinct from movement.adda_id
),
loading_advance_duplicates as (
  select reference_id, count(*) row_count
  from public.cashbook_entries
  where reference_type = 'loading_advance'
    and reference_id is not null
  group by reference_id
  having count(*) > 1
),
checks(check_name, status, details, blocking) as (
  select
    'BASE_RELATIONS',
    case when count(*) = 0 then 'PASS' else 'FAIL' end,
    case when count(*) = 0 then 'All required deployed relations exist.'
      else 'Missing: ' || string_agg(relation_name, ', ' order by relation_name) end,
    true
  from missing_relations

  union all
  select
    'REQUIRED_COLUMN_CONTRACT',
    case when count(*) = 0 then 'PASS' else 'FAIL' end,
    case when count(*) = 0 then 'Loading bridge columns have compatible types and required nullability.'
      else 'Missing/incompatible: ' || string_agg(
        table_name || '.' || column_name || ' expected ' || expected_type ||
        ' nullable=' || coalesce(required_nullable, 'ANY') ||
        ', actual ' || coalesce(actual_type, 'MISSING') ||
        ' nullable=' || coalesce(actual_nullable, 'MISSING'),
        '; ' order by table_name, column_name
      ) end,
    true
  from incompatible_columns

  union all
  select
    'LOADINGS_INSERT_DEFAULT_CONTRACT',
    case when count(*) = 0 then 'PASS' else 'FAIL' end,
    case when count(*) = 0
      then 'Every non-null Loading column omitted by the bridge has a database default/identity/generated value.'
      else 'Bridge cannot supply required omitted column(s): ' ||
        string_agg(column_name, ', ' order by column_name)
    end,
    true
  from unsatisfied_implicit_loading_columns

  union all
  select
    'ACTUAL_LOADINGS_COLUMN_CONTRACTS',
    'INFO',
    string_agg(
      column_name || ': type=' || data_type || '/' || udt_name ||
      ', nullable=' || is_nullable ||
      ', default=' || coalesce(column_default, 'NULL') ||
      ', bridge_value=' || supplied_value ||
      ', compatible=' || bridge_insert_compatible,
      '; ' order by column_name
    ),
    false
  from loadings_column_contracts

  union all
  select
    'MOVEMENT_GROUP_CONTEXT_RESOLVER',
    case when to_regprocedure('public.ut_resolve_movement_group_context(uuid)') is not null then 'PASS' else 'FAIL' end,
    'The deployed direct Movement Group Adda/Vehicle resolver must exist.',
    true

  union all
  select
    'TENANT_HELPERS',
    case when to_regprocedure('public.current_user_adda_id()') is not null
      and to_regprocedure('public.current_user_role()') is not null
      and to_regprocedure('public.is_super_admin()') is not null
      then 'PASS' else 'FAIL' end,
    'Existing current-user Adda, role, and Super Admin helpers must exist.',
    true

  union all
  select
    'DIRECT_VOUCHER_SAVE_PATH',
    case when to_regprocedure('public.save_voucher_with_movement_group(text,text,date,date,text,uuid,text[])') is not null
      then 'PASS' else 'FAIL' end,
    'The deployed Voucher save RPC must accept authoritative Movement Group plus real Loading IDs.',
    true

  union all
  select
    'LOADINGS_TRIGGER_SET',
    case when count(*) = 2
      and count(*) filter (where tgname in ('loadings_audit_log_trigger', 'loadings_sync_advance_cashbook')) = 2
      and count(*) filter (where tgenabled <> 'D') = 2
      then 'PASS' else 'FAIL' end,
    count(*) || ' enabled/non-internal Loading trigger definition(s) found: ' ||
      coalesce(string_agg(tgname, ', ' order by tgname), 'none') || '.',
    true
  from loading_triggers

  union all
  select
    'ZERO_ADVANCE_CASHBOOK_PATH',
    case when exists (
      select 1
      from advance_trigger_definition definition
      where definition.normalized_definition like '%performpublic.ut_sync_loading_advance_cashbook(new.id::text);%'
    ) and exists (
      select 1
      from advance_sync_definition definition
      where definition.normalized_definition like '%original_advance:=coalesce(loading_record.advance_amount,0)-receipt_total;%'
        and definition.normalized_definition like '%iforiginal_advance<=0then%'
        and split_part(
          split_part(definition.normalized_definition, 'iforiginal_advance<=0then', 2),
          'endif;',
          1
        ) like '%deletefrompublic.cashbook_entries%reference_type=''loading_advance''%return;%'
        and split_part(
          split_part(definition.normalized_definition, 'iforiginal_advance<=0then', 2),
          'endif;',
          1
        ) not like '%insertintopublic.cashbook_entries%'
        and position('insertintopublic.cashbook_entries' in definition.normalized_definition)
          > position('iforiginal_advance<=0then' in definition.normalized_definition)
    ) then 'PASS' else 'FAIL' end,
    'The Loading trigger delegates to ut_sync_loading_advance_cashbook(text); its computed zero-or-negative branch removes only the exact loading_advance reference and returns before any Cashbook INSERT.',
    true

  union all
  select
    'GROUP_LOADING_CONTEXT_INTEGRITY',
    case when count(*) = 0 then 'PASS' else 'FAIL' end,
    count(*) || ' authoritative group Loading relationship(s) have Vehicle/Adda mismatches.',
    true
  from group_loading_context_mismatches

  union all
  select
    'GROUP_MEMBER_LOADING_UNAMBIGUOUS',
    case when count(*) = 0 then 'PASS' else 'FAIL' end,
    count(*) || ' eligible completed group Bilty member(s) have multiple authoritative Loading rows.',
    true
  from member_loading_ambiguities

  union all
  select
    'GENERATED_LOADING_NUMBER_AVAILABLE',
    case when count(*) = 0 then 'PASS' else 'FAIL' end,
    count(*) || ' deterministic Bilty Loading number(s) are already used by an unrelated Loading.',
    true
  from generated_loading_number_conflicts

  union all
  select
    'LOADING_ADVANCE_CASHBOOK_UNIQUENESS',
    case when count(*) = 0 then 'PASS' else 'FAIL' end,
    count(*) || ' duplicate loading_advance Cashbook reference(s) exist.',
    true
  from loading_advance_duplicates

  union all
  select
    'TARGET_RPC_ABSENT',
    case when to_regprocedure('public.prepare_voucher_movement_group_loading(uuid)') is null then 'PASS' else 'FAIL' end,
    'The proposed RPC name must not already be deployed.',
    true

  union all
  select
    'MIGRATION_HISTORY_PENDING',
    case when not exists (
      select 1 from supabase_migrations.schema_migrations history
      where history.version = '202609080002'
    ) then 'PASS' else 'FAIL' end,
    'Migration version 202609080002 must not already be recorded.',
    true

  union all
  select
    'ZERO_LOADING_COMPLETED_GROUPS',
    'INFO',
    count(*) || ' valid completed Movement Group(s) currently have zero authoritative Loading links.',
    false
  from zero_loading_groups

  union all
  select
    'NO_HISTORICAL_BACKFILL_REQUIRED',
    'PASS',
    'The migration installs an on-demand RPC only; it does not backfill or alter existing Loadings, Bilties, Vouchers, or accounting rows.',
    true
),
summary as (
  select
    count(*) filter (where blocking and status = 'FAIL') blocking_failures,
    count(*) filter (where status = 'PASS') passed_checks,
    count(*) filter (where status = 'INFO') informational_checks
  from checks
),
output_rows(sort_order, check_name, status, details) as (
  select
    0,
    'OVERALL_VOUCHER_GROUP_LOADING_BRIDGE_PREFLIGHT',
    case when blocking_failures = 0 then 'PASS' else 'FAIL' end,
    blocking_failures || ' blocking check(s) failed; ' || passed_checks ||
      ' passed; ' || informational_checks || ' informational.'
  from summary
  union all
  select 1, check_name, status, details from checks
)
select check_name, status, details
from output_rows
order by sort_order, check_name;
