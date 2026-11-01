/*
  UT SOFTWARE — BILTY FOUNDATION DEPLOYMENT PREFLIGHT
  Target: supabase/migrations/202608160001_bilty_foundation.sql

  This script is strictly read-only. Apply the migration only when OVERALL is PASS.
*/

with
required_relations(object_name) as (
  values
    ('public.addas'),
    ('public.profiles'),
    ('public.bookings'),
    ('public.loadings'),
    ('public.parties'),
    ('public.brokers'),
    ('public.vehicles')
),
relation_checks as (
  select
    10 as sort_order,
    'REQUIRED_RELATION_' || upper(replace(object_name, 'public.', '')) as check_name,
    case when to_regclass(object_name) is null then 'FAIL' else 'PASS' end as status,
    case
      when to_regclass(object_name) is null then object_name || ' is missing'
      else object_name || ' exists'
    end as details
  from required_relations
),
expected_columns(table_name, column_name, allowed_types) as (
  values
    ('addas', 'id', array['uuid']),
    ('profiles', 'id', array['uuid']),
    ('profiles', 'role', array['text', 'varchar']),
    ('profiles', 'adda_id', array['uuid']),
    ('profiles', 'is_active', array['bool']),
    ('bookings', 'id', array['uuid']),
    ('bookings', 'adda_id', array['uuid']),
    ('bookings', 'party_id', array['uuid']),
    ('bookings', 'booking_no', array['text', 'varchar']),
    ('bookings', 'booking_date', array['date']),
    ('bookings', 'sender_name', array['text', 'varchar']),
    ('bookings', 'sender_phone', array['text', 'varchar']),
    ('bookings', 'receiver_name', array['text', 'varchar']),
    ('bookings', 'receiver_phone', array['text', 'varchar']),
    ('bookings', 'from_city', array['text', 'varchar']),
    ('bookings', 'to_city', array['text', 'varchar']),
    ('bookings', 'goods_name', array['text', 'varchar']),
    ('bookings', 'quantity', array['numeric', 'int2', 'int4', 'int8', 'float4', 'float8']),
    ('bookings', 'weight', array['numeric', 'int2', 'int4', 'int8', 'float4', 'float8']),
    ('bookings', 'freight', array['numeric', 'int2', 'int4', 'int8', 'float4', 'float8']),
    ('bookings', 'status', array['text', 'varchar']),
    ('loadings', 'id', array['int8']),
    ('loadings', 'booking_id', array['uuid']),
    ('parties', 'id', array['uuid']),
    ('parties', 'adda_id', array['uuid']),
    ('parties', 'is_active', array['bool']),
    ('brokers', 'id', array['uuid']),
    ('vehicles', 'id', array['uuid']),
    ('vehicles', 'adda_id', array['uuid'])
),
column_checks as (
  select
    20 as sort_order,
    'COLUMN_' || upper(expected.table_name) || '_' || upper(expected.column_name) as check_name,
    case
      when actual.column_name is not null
       and actual.udt_name = any(expected.allowed_types) then 'PASS'
      else 'FAIL'
    end as status,
    case
      when actual.column_name is null then
        format('public.%I.%I is missing; expected %s', expected.table_name, expected.column_name, array_to_string(expected.allowed_types, '/'))
      else
        format('deployed type=%s; expected=%s; nullable=%s', actual.udt_name, array_to_string(expected.allowed_types, '/'), actual.is_nullable)
    end as details
  from expected_columns as expected
  left join information_schema.columns as actual
    on actual.table_schema = 'public'
   and actual.table_name = expected.table_name
   and actual.column_name = expected.column_name
),
primary_key_check as (
  select
    30 as sort_order,
    'BOOKINGS_UUID_PRIMARY_KEY' as check_name,
    case when exists (
      select 1
      from pg_constraint as constraint_info
      where constraint_info.contype = 'p'
        and constraint_info.conrelid = to_regclass('public.bookings')
        and constraint_info.convalidated
        and array_length(constraint_info.conkey, 1) = 1
        and (
          select attribute_info.attname
          from pg_attribute as attribute_info
          where attribute_info.attrelid = constraint_info.conrelid
            and attribute_info.attnum = constraint_info.conkey[1]
        ) = 'id'
    ) then 'PASS' else 'FAIL' end as status,
    coalesce((
      select string_agg(pg_get_constraintdef(c.oid, true), ' | ')
      from pg_constraint as c
      where c.contype = 'p' and c.conrelid = to_regclass('public.bookings')
    ), 'No bookings primary key found') as details
),
required_fks(check_name, source_table, source_column, target_table, target_column) as (
  values
    ('LOADINGS_BOOKING_ID_FOREIGN_KEY', 'loadings', 'booking_id', 'bookings', 'id'),
    ('BOOKINGS_PARTY_ID_FOREIGN_KEY', 'bookings', 'party_id', 'parties', 'id'),
    ('PARTIES_ADDA_ID_FOREIGN_KEY', 'parties', 'adda_id', 'addas', 'id')
),
fk_checks as (
  select
    40 as sort_order,
    expected.check_name,
    case when exists (
      select 1
      from pg_constraint as constraint_info
      where constraint_info.contype = 'f'
        and constraint_info.conrelid = to_regclass(format('public.%I', expected.source_table))
        and constraint_info.confrelid = to_regclass(format('public.%I', expected.target_table))
        and constraint_info.convalidated
        and array_length(constraint_info.conkey, 1) = 1
        and array_length(constraint_info.confkey, 1) = 1
        and (
          select source_attribute.attname
          from pg_attribute as source_attribute
          where source_attribute.attrelid = constraint_info.conrelid
            and source_attribute.attnum = constraint_info.conkey[1]
        ) = expected.source_column
        and (
          select target_attribute.attname
          from pg_attribute as target_attribute
          where target_attribute.attrelid = constraint_info.confrelid
            and target_attribute.attnum = constraint_info.confkey[1]
        ) = expected.target_column
    ) then 'PASS' else 'FAIL' end as status,
    coalesce((
      select string_agg(
        format('%s: %s; validated=%s', constraint_info.conname, pg_get_constraintdef(constraint_info.oid, true), constraint_info.convalidated),
        ' | '
      )
      from pg_constraint as constraint_info
      where constraint_info.contype = 'f'
        and constraint_info.conrelid = to_regclass(format('public.%I', expected.source_table))
        and constraint_info.confrelid = to_regclass(format('public.%I', expected.target_table))
    ), format('No %s.%s -> %s.%s foreign key found', expected.source_table, expected.source_column, expected.target_table, expected.target_column)) as details
  from required_fks as expected
),
data_integrity_checks as (
  select
    50 as sort_order,
    'BOOKINGS_ADDA_DATA_INTEGRITY' as check_name,
    case when count(*) filter (where booking.adda_id is not null and adda.id is null) = 0 then 'PASS' else 'FAIL' end as status,
    format(
      'non-null orphan Adda references=%s; legacy NULL adda_id rows=%s. A physical bookings.adda_id FK is not required by this Bilty migration; the RPC validates Adda existence.',
      count(*) filter (where booking.adda_id is not null and adda.id is null),
      count(*) filter (where booking.adda_id is null)
    ) as details
  from public.bookings as booking
  left join public.addas as adda on adda.id = booking.adda_id

  union all

  select
    51,
    'VEHICLES_ADDA_DATA_INTEGRITY',
    case when count(*) filter (where vehicle.adda_id is not null and adda.id is null) = 0 then 'PASS' else 'FAIL' end,
    format(
      'non-null orphan Adda references=%s; NULL adda_id rows=%s. A physical vehicles.adda_id FK is not required by this Bilty migration; self-vehicle selection is validated against the requested Adda.',
      count(*) filter (where vehicle.adda_id is not null and adda.id is null),
      count(*) filter (where vehicle.adda_id is null)
    )
  from public.vehicles as vehicle
  left join public.addas as adda on adda.id = vehicle.adda_id

  union all

  select
    52,
    'BOOKING_PARTY_ADDA_DATA_INTEGRITY',
    case when count(*) = 0 then 'PASS' else 'FAIL' end,
    format('existing cross-Adda or orphan Party assignments=%s', count(*))
  from public.bookings as booking
  left join public.parties as party on party.id = booking.party_id
  where booking.party_id is not null
    and (party.id is null or party.adda_id is distinct from booking.adda_id)
),
duplicate_numbers as (
  select
    booking.adda_id,
    lower(btrim(booking.booking_no)) as normalized_number,
    count(*) as duplicate_count,
    string_agg(booking.id::text, ', ' order by booking.id) as ids
  from public.bookings as booking
  where booking.booking_no is not null and btrim(booking.booking_no) <> ''
  group by booking.adda_id, lower(btrim(booking.booking_no))
  having count(*) > 1
),
duplicate_number_check as (
  select
    60 as sort_order,
    'ADDA_SCOPED_BILTY_NUMBER_UNIQUENESS' as check_name,
    case when count(*) = 0 then 'PASS' else 'FAIL' end as status,
    case when count(*) = 0 then
      'No duplicates for adda_id + lower(trim(booking_no))'
    else
      string_agg(format('adda=%s; number=%s; count=%s; ids=%s', coalesce(adda_id::text, 'NULL'), normalized_number, duplicate_count, ids), ' | ')
    end as details
  from duplicate_numbers
),
party_trigger_check as (
  select
    70 as sort_order,
    'BOOKINGS_PARTY_ADDA_TRIGGER' as check_name,
    case when count(*) filter (
      where trigger_info.tgname = 'bookings_validate_party_adda'
        and trigger_info.tgenabled <> 'D'
    ) = 1 then 'PASS' else 'FAIL' end as status,
    coalesce(string_agg(
      format('%s; enabled=%s; definition=%s', trigger_info.tgname, trigger_info.tgenabled, pg_get_triggerdef(trigger_info.oid, true)),
      ' | '
    ) filter (where trigger_info.tgname = 'bookings_validate_party_adda'), 'Trigger is missing') as details
  from pg_trigger as trigger_info
  where trigger_info.tgrelid = to_regclass('public.bookings')
    and not trigger_info.tgisinternal
),
additional_trigger_check as (
  select
    71 as sort_order,
    'ADDITIONAL_BOOKINGS_TRIGGER_REVIEW' as check_name,
    case when count(*) filter (
      where trigger_info.tgenabled <> 'D'
        and trigger_info.tgname not in ('bookings_validate_party_adda', 'bookings_audit_log_trigger')
    ) = 0 then 'PASS' else 'FAIL' end as status,
    case when count(*) filter (
      where trigger_info.tgenabled <> 'D'
        and trigger_info.tgname not in ('bookings_validate_party_adda', 'bookings_audit_log_trigger')
    ) = 0 then
      'Only known safe enabled triggers are present. bookings_audit_log_trigger is explicitly allowed and preserved.'
    else
      string_agg(
        format('%s; enabled=%s; definition=%s', trigger_info.tgname, trigger_info.tgenabled, pg_get_triggerdef(trigger_info.oid, true)),
        ' | ' order by trigger_info.tgname
      ) filter (
        where trigger_info.tgenabled <> 'D'
          and trigger_info.tgname not in ('bookings_validate_party_adda', 'bookings_audit_log_trigger')
      )
    end as details
  from pg_trigger as trigger_info
  where trigger_info.tgrelid = to_regclass('public.bookings')
    and not trigger_info.tgisinternal
),
helper_functions(function_signature, expected_result) as (
  values
    ('public.current_user_adda_id()', 'uuid'),
    ('public.is_super_admin()', 'boolean')
),
helper_checks as (
  select
    80 as sort_order,
    'HELPER_' || upper(replace(replace(helper.function_signature, 'public.', ''), '()', '')) as check_name,
    case
      when to_regprocedure(helper.function_signature) is not null
       and pg_get_function_result(to_regprocedure(helper.function_signature)) = helper.expected_result
      then 'PASS' else 'FAIL'
    end as status,
    case
      when to_regprocedure(helper.function_signature) is null then helper.function_signature || ' is missing'
      else format('%s returns %s', helper.function_signature, pg_get_function_result(to_regprocedure(helper.function_signature)))
    end as details
  from helper_functions as helper
),
rls_targets(table_name) as (
  values ('addas'), ('profiles'), ('bookings'), ('parties'), ('vehicles')
),
rls_checks as (
  select
    90 as sort_order,
    'RLS_' || upper(target.table_name) as check_name,
    case when relation_info.relrowsecurity and count(policy_info.policyname) > 0 then 'PASS' else 'FAIL' end as status,
    format(
      'enabled=%s; policy_count=%s; policies=%s',
      relation_info.relrowsecurity,
      count(policy_info.policyname),
      coalesce(jsonb_agg(jsonb_build_object('name', policy_info.policyname, 'command', policy_info.cmd) order by policy_info.policyname) filter (where policy_info.policyname is not null), '[]'::jsonb)::text
    ) as details
  from rls_targets as target
  join pg_class as relation_info on relation_info.oid = to_regclass(format('public.%I', target.table_name))
  left join pg_policies as policy_info
    on policy_info.schemaname = 'public' and policy_info.tablename = target.table_name
  group by target.table_name, relation_info.relrowsecurity
),
broker_contract_check as (
  select
    95 as sort_order,
    'BROKERS_EXISTING_GLOBAL_ACCESS_CONTRACT' as check_name,
    case
      when not relation_info.relrowsecurity then 'PASS'
      when count(policy_info.policyname) > 0 then 'PASS'
      else 'FAIL'
    end as status,
    format(
      'RLS enabled=%s; policy_count=%s. The current Broker master has no confirmed adda_id and uses direct browser CRUD. Disabled RLS is therefore documented as the existing global contract, not a Bilty migration blocker.',
      relation_info.relrowsecurity,
      count(policy_info.policyname)
    ) as details
  from pg_class as relation_info
  left join pg_policies as policy_info
    on policy_info.schemaname = 'public' and policy_info.tablename = 'brokers'
  where relation_info.oid = to_regclass('public.brokers')
  group by relation_info.relrowsecurity
),
bilty_booking_columns(column_name, allowed_types, require_not_null, require_zero_default) as (
  values
    ('bilty_group_id', array['uuid'], false, false),
    ('trip_type', array['text', 'varchar'], false, false),
    ('freight_type', array['text', 'varchar'], false, false),
    ('bilty_type', array['text', 'varchar'], false, false),
    ('broker_id', array['uuid'], false, false),
    ('reference_no', array['text', 'varchar'], false, false),
    ('departure_date', array['date'], false, false),
    ('arrival_date', array['date'], false, false),
    ('vehicle_id', array['uuid'], false, false),
    ('external_vehicle_no', array['text', 'varchar'], false, false),
    ('external_vehicle_type', array['text', 'varchar'], false, false),
    ('external_owner_name', array['text', 'varchar'], false, false),
    ('container_no', array['text', 'varchar'], false, false),
    ('container_size', array['text', 'varchar'], false, false),
    ('container_weight', array['numeric'], false, false),
    ('container_serial', array['text', 'varchar'], false, false),
    ('container_port', array['text', 'varchar'], false, false),
    ('clearing_agent', array['text', 'varchar'], false, false),
    ('shipping_line', array['text', 'varchar'], false, false),
    ('container_cargo', array['text', 'varchar'], false, false),
    ('advance_vehicle', array['numeric'], true, true),
    ('advance_bilty', array['numeric'], true, true),
    ('advance_commission', array['numeric'], true, true),
    ('overweight_charges', array['numeric'], true, true),
    ('mt_charges_receivable', array['numeric'], true, true),
    ('mt_charges_payable', array['numeric'], true, true),
    ('party_commission', array['numeric'], true, true),
    ('broker_commission', array['numeric'], true, true),
    ('advance_brokerage', array['numeric'], true, true),
    ('other_income', array['numeric'], true, true),
    ('deduction_adjustment', array['numeric'], true, true),
    ('account_type', array['text', 'varchar'], false, false),
    ('from_location_id', array['uuid'], false, false),
    ('to_location_id', array['uuid'], false, false)
),
bilty_booking_column_checks as (
  select
    100 as sort_order,
    'BILTY_COLUMN_' || upper(expected.column_name) as check_name,
    case
      when actual.column_name is null then 'PASS'
      when actual.udt_name <> all(expected.allowed_types) then 'FAIL'
      when expected.require_not_null and actual.is_nullable <> 'NO' then 'FAIL'
      when expected.require_zero_default and coalesce(actual.column_default, '') !~ '(^|[^0-9])0([.:]|$)' then 'FAIL'
      else 'PASS'
    end as status,
    case
      when actual.column_name is null then format('absent; migration will add public.bookings.%I', expected.column_name)
      else format(
        'present; type=%s; nullable=%s; default=%s; expected type=%s%s',
        actual.udt_name,
        actual.is_nullable,
        coalesce(actual.column_default, 'NULL'),
        array_to_string(expected.allowed_types, '/'),
        case when expected.require_not_null then '; NOT NULL with zero default required for an already-present financial column' else '' end
      )
    end as details
  from bilty_booking_columns as expected
  left join information_schema.columns as actual
    on actual.table_schema = 'public'
   and actual.table_name = 'bookings'
   and actual.column_name = expected.column_name
),
new_relation_columns(relation_name, column_name, allowed_types, required_nullable, generation_required, default_pattern) as (
  values
    ('pakistan_locations', 'id', array['uuid'], 'NO', false, '%gen_random_uuid()%'),
    ('pakistan_locations', 'parent_id', array['uuid'], 'YES', false, null),
    ('pakistan_locations', 'location_type', array['text', 'varchar'], 'NO', false, null),
    ('pakistan_locations', 'name', array['text', 'varchar'], 'NO', false, null),
    ('pakistan_locations', 'normalized_name', array['text', 'varchar'], 'YES', true, null),
    ('pakistan_locations', 'is_active', array['bool'], 'NO', false, '%true%'),
    ('pakistan_locations', 'created_at', array['timestamptz'], 'NO', false, '%now()%'),
    ('pakistan_locations', 'updated_at', array['timestamptz'], 'NO', false, '%now()%'),
    ('bilty_items', 'id', array['uuid'], 'NO', false, '%gen_random_uuid()%'),
    ('bilty_items', 'bilty_id', array['uuid'], 'NO', false, null),
    ('bilty_items', 'line_no', array['int4'], 'NO', false, '%1%'),
    ('bilty_items', 'goods_name', array['text', 'varchar'], 'NO', false, null),
    ('bilty_items', 'quantity', array['numeric'], 'NO', false, null),
    ('bilty_items', 'weight', array['numeric'], 'YES', false, null),
    ('bilty_items', 'unit', array['text', 'varchar'], 'NO', false, null),
    ('bilty_items', 'remarks', array['text', 'varchar'], 'YES', false, null),
    ('bilty_items', 'created_at', array['timestamptz'], 'NO', false, '%now()%'),
    ('bilty_items', 'updated_at', array['timestamptz'], 'NO', false, '%now()%')
),
new_relation_column_checks as (
  select
    110 as sort_order,
    'BILTY_RELATION_COLUMN_' || upper(expected.relation_name) || '_' || upper(expected.column_name) as check_name,
    case
      when to_regclass(format('public.%I', expected.relation_name)) is null then 'PASS'
      when actual.column_name is null then 'FAIL'
      when actual.udt_name <> all(expected.allowed_types) then 'FAIL'
      when actual.is_nullable <> expected.required_nullable then 'FAIL'
      when expected.generation_required and actual.is_generated <> 'ALWAYS' then 'FAIL'
      when expected.default_pattern is not null and coalesce(actual.column_default, '') not ilike expected.default_pattern then 'FAIL'
      else 'PASS'
    end as status,
    case
      when to_regclass(format('public.%I', expected.relation_name)) is null then format('public.%I is absent; migration will create its complete contract', expected.relation_name)
      when actual.column_name is null then format('existing public.%I is missing required column %I', expected.relation_name, expected.column_name)
      else format('present; type=%s; nullable=%s; generated=%s; default=%s; expected type=%s, nullable=%s%s%s', actual.udt_name, actual.is_nullable, actual.is_generated, coalesce(actual.column_default, 'NULL'), array_to_string(expected.allowed_types, '/'), expected.required_nullable, case when expected.generation_required then ', generated ALWAYS' else '' end, case when expected.default_pattern is not null then ', default matching ' || expected.default_pattern else '' end)
    end as details
  from new_relation_columns as expected
  left join information_schema.columns as actual
    on actual.table_schema = 'public'
   and actual.table_name = expected.relation_name
   and actual.column_name = expected.column_name
),
expected_constraints(relation_name, constraint_name, definition_pattern) as (
  values
    ('bookings', 'bookings_trip_type_check', '%trip_type%outbound%return%local%'),
    ('bookings', 'bookings_bilty_dates_check', '%arrival_date%departure_date%'),
    ('bookings', 'bookings_bilty_account_type_check', '%account_type%party_account%mt_account%other_account%'),
    ('bookings', 'bookings_bilty_financial_values_check', '%advance_vehicle%deduction_adjustment%'),
    ('bookings', 'bookings_freight_type_check', '%freight_type%paid%advance%to_pay%'),
    ('bookings', 'bookings_bilty_type_check', '%bilty_type%self_vehicle%other_vehicle%'),
    ('bookings', 'bookings_broker_id_fkey', '%FOREIGN KEY (broker_id)%REFERENCES brokers(id)%ON DELETE RESTRICT%'),
    ('bookings', 'bookings_vehicle_id_fkey', '%FOREIGN KEY (vehicle_id)%REFERENCES vehicles(id)%ON DELETE RESTRICT%'),
    ('bookings', 'bookings_from_location_id_fkey', '%FOREIGN KEY (from_location_id)%REFERENCES pakistan_locations(id)%ON DELETE RESTRICT%'),
    ('bookings', 'bookings_to_location_id_fkey', '%FOREIGN KEY (to_location_id)%REFERENCES pakistan_locations(id)%ON DELETE RESTRICT%'),
    ('pakistan_locations', 'pakistan_locations_pkey', '%PRIMARY KEY (id)%'),
    ('pakistan_locations', 'pakistan_locations_parent_id_fkey', '%FOREIGN KEY (parent_id)%REFERENCES pakistan_locations(id)%ON DELETE RESTRICT%'),
    ('pakistan_locations', 'pakistan_locations_type_check', '%location_type%province%district%tehsil%city%'),
    ('pakistan_locations', 'pakistan_locations_name_check', '%btrim(name)%'),
    ('bilty_items', 'bilty_items_pkey', '%PRIMARY KEY (id)%'),
    ('bilty_items', 'bilty_items_bilty_id_fkey', '%FOREIGN KEY (bilty_id)%REFERENCES bookings(id)%ON DELETE CASCADE%'),
    ('bilty_items', 'bilty_items_line_no_check', '%line_no > 0%'),
    ('bilty_items', 'bilty_items_goods_name_check', '%btrim(goods_name)%'),
    ('bilty_items', 'bilty_items_quantity_check', '%quantity >%'),
    ('bilty_items', 'bilty_items_weight_check', '%weight IS NULL%weight >%'),
    ('bilty_items', 'bilty_items_unit_check', '%btrim(unit)%'),
    ('bilty_items', 'bilty_items_bilty_line_key', '%UNIQUE (bilty_id, line_no)%')
),
constraint_checks as (
  select
    120 as sort_order,
    'BILTY_CONSTRAINT_' || upper(expected.constraint_name) as check_name,
    case
      when expected.relation_name in ('pakistan_locations', 'bilty_items')
       and to_regclass(format('public.%I', expected.relation_name)) is null then 'PASS'
      when constraint_info.oid is null then
        case when expected.relation_name = 'bookings' then 'PASS' else 'FAIL' end
      when not constraint_info.convalidated then 'FAIL'
      when pg_get_constraintdef(constraint_info.oid, true) not ilike expected.definition_pattern then 'FAIL'
      else 'PASS'
    end as status,
    case
      when expected.relation_name in ('pakistan_locations', 'bilty_items')
       and to_regclass(format('public.%I', expected.relation_name)) is null then format('relation absent; migration will create %s', expected.constraint_name)
      when constraint_info.oid is null and expected.relation_name = 'bookings' then format('absent; migration will add %s', expected.constraint_name)
      when constraint_info.oid is null then format('existing public.%I is missing required inline constraint %s; CREATE TABLE IF NOT EXISTS would not repair it', expected.relation_name, expected.constraint_name)
      else format('validated=%s; definition=%s', constraint_info.convalidated, pg_get_constraintdef(constraint_info.oid, true))
    end as details
  from expected_constraints as expected
  left join pg_constraint as constraint_info
    on constraint_info.conrelid = to_regclass(format('public.%I', expected.relation_name))
   and constraint_info.conname = expected.constraint_name
),
expected_indexes(index_name, relation_name, must_be_unique, definition_pattern) as (
  values
    ('pakistan_locations_hierarchy_name_uidx', 'pakistan_locations', true, '%coalesce(parent_id,%location_type%normalized_name%'),
    ('pakistan_locations_search_idx', 'pakistan_locations', false, '%normalized_name%is_active%'),
    ('bookings_adda_bilty_number_uidx', 'bookings', true, '%adda_id%lower(btrim(booking_no))%WHERE%booking_no IS NOT NULL%btrim(booking_no)%'),
    ('bookings_adda_group_idx', 'bookings', false, '%adda_id%bilty_group_id%'),
    ('bookings_broker_id_idx', 'bookings', false, '%broker_id%'),
    ('bookings_vehicle_id_idx', 'bookings', false, '%vehicle_id%'),
    ('bookings_from_location_id_idx', 'bookings', false, '%from_location_id%'),
    ('bookings_to_location_id_idx', 'bookings', false, '%to_location_id%'),
    ('bilty_items_bilty_id_idx', 'bilty_items', false, '%bilty_id%line_no%')
),
index_checks as (
  select
    130 as sort_order,
    'BILTY_INDEX_' || upper(expected.index_name) as check_name,
    case
      when index_info.oid is null then 'PASS'
      when index_info.indrelid <> to_regclass(format('public.%I', expected.relation_name)) then 'FAIL'
      when not index_info.indisvalid or not index_info.indisready then 'FAIL'
      when index_info.indisunique <> expected.must_be_unique then 'FAIL'
      when pg_get_indexdef(index_info.indexrelid) not ilike expected.definition_pattern then 'FAIL'
      else 'PASS'
    end as status,
    case
      when index_info.oid is null then format('absent; migration will create %s', expected.index_name)
      else format('relation=%s; valid=%s; ready=%s; unique=%s; definition=%s', index_info.indrelid::regclass, index_info.indisvalid, index_info.indisready, index_info.indisunique, pg_get_indexdef(index_info.indexrelid))
    end as details
  from expected_indexes as expected
  left join (
    select index_class.oid, index_meta.*
    from pg_class as index_class
    join pg_namespace as index_namespace on index_namespace.oid = index_class.relnamespace
    join pg_index as index_meta on index_meta.indexrelid = index_class.oid
    where index_namespace.nspname = 'public' and index_class.relkind = 'i'
  ) as index_info on index_info.oid = to_regclass(format('public.%I', expected.index_name))
),
new_relation_rls_checks as (
  select
    140 as sort_order,
    'BILTY_RLS_' || upper(target.relation_name) as check_name,
    case
      when relation_info.oid is null then 'PASS'
      when extra_policy.extra_count > 0 then 'FAIL'
      else 'PASS'
    end as status,
    case
      when relation_info.oid is null then format('public.%I absent; migration will create it, enable RLS, and create the final policies', target.relation_name)
      else format('present; RLS currently enabled=%s (migration enables it); expected policies are dropped/recreated; unexpected extra policies=%s; policy inventory=%s', relation_info.relrowsecurity, extra_policy.extra_count, extra_policy.policy_names)
    end as details
  from (values
    ('pakistan_locations', array['pakistan_locations_authenticated_read', 'pakistan_locations_super_admin_manage']),
    ('bilty_items', array['bilty_items_tenant_read', 'bilty_items_tenant_insert', 'bilty_items_tenant_update', 'bilty_items_tenant_delete'])
  ) as target(relation_name, expected_policy_names)
  left join pg_class as relation_info on relation_info.oid = to_regclass(format('public.%I', target.relation_name))
  cross join lateral (
    select
      count(*) filter (where policy.policyname <> all(target.expected_policy_names)) as extra_count,
      coalesce(string_agg(policy.policyname, ', ' order by policy.policyname), '(none)') as policy_names
    from pg_policies as policy
    where policy.schemaname = 'public' and policy.tablename = target.relation_name
  ) as extra_policy
),
rpc_inventory as (
  select
    procedure_info.oid,
    pg_get_function_identity_arguments(procedure_info.oid) as identity_arguments,
    pg_get_function_result(procedure_info.oid) as result_type,
    procedure_info.prosecdef,
    language_info.lanname
  from pg_proc as procedure_info
  join pg_namespace as namespace_info on namespace_info.oid = procedure_info.pronamespace
  join pg_language as language_info on language_info.oid = procedure_info.prolang
  where namespace_info.nspname = 'public'
    and procedure_info.proname = 'save_bilty_with_items'
),
rpc_deployment_state_check as (
  select
    150 as sort_order,
    'SAVE_BILTY_WITH_ITEMS_DEPLOYMENT_STATE' as check_name,
    case
      when count(*) = 0 then 'PASS'
      when count(*) = 1
       and count(*) filter (
         where oid in (
           to_regprocedure('public.save_bilty_with_items(uuid,uuid,text,date,uuid,text,text,text,uuid,uuid,text,uuid,text,text,text,uuid,uuid,text,text,text,text,numeric,jsonb)'),
           to_regprocedure('public.save_bilty_with_items(uuid,uuid,text,date,uuid,text,text,text,uuid,uuid,text,date,date,uuid,text,text,text,text,text,numeric,text,text,text,text,text,uuid,uuid,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,jsonb)')
         )
       ) = 1
       and bool_and(result_type = 'uuid' and not prosecdef and lanname = 'plpgsql') then 'PASS'
      else 'FAIL'
    end as status,
    case
      when count(*) = 0 then 'fully pending: no RPC exists; migration will create the final 45-parameter contract'
      else string_agg(format('args=(%s); returns=%s; security_definer=%s; language=%s', identity_arguments, result_type, prosecdef, lanname), ' | ' order by identity_arguments)
    end as details
  from rpc_inventory
),
rpc_final_signature_check as (
  select
    151 as sort_order,
    'SAVE_BILTY_WITH_ITEMS_FINAL_SIGNATURE' as check_name,
    case
      when count(*) = 0 then 'PASS'
      when count(*) = 1
       and count(*) filter (
         where oid = to_regprocedure('public.save_bilty_with_items(uuid,uuid,text,date,uuid,text,text,text,uuid,uuid,text,date,date,uuid,text,text,text,text,text,numeric,text,text,text,text,text,uuid,uuid,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,jsonb)')
           and result_type = 'uuid' and not prosecdef and lanname = 'plpgsql'
       ) = 1 then 'PASS'
      when count(*) = 1
       and count(*) filter (
         where oid = to_regprocedure('public.save_bilty_with_items(uuid,uuid,text,date,uuid,text,text,text,uuid,uuid,text,uuid,text,text,text,uuid,uuid,text,text,text,text,numeric,jsonb)')
           and result_type = 'uuid' and not prosecdef and lanname = 'plpgsql'
       ) = 1 then 'PASS'
      else 'FAIL'
    end as status,
    case
      when count(*) = 0 then 'final signature is not deployed; safe fully-pending state and migration will create it'
      when count(*) filter (where oid = to_regprocedure('public.save_bilty_with_items(uuid,uuid,text,date,uuid,text,text,text,uuid,uuid,text,date,date,uuid,text,text,text,text,text,numeric,text,text,text,text,text,uuid,uuid,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,jsonb)')) = 1
        then 'final 45-parameter signature is already deployed with the required uuid/SECURITY INVOKER/plpgsql contract'
      when count(*) filter (where oid = to_regprocedure('public.save_bilty_with_items(uuid,uuid,text,date,uuid,text,text,text,uuid,uuid,text,uuid,text,text,text,uuid,uuid,text,text,text,text,numeric,jsonb)')) = 1
        then 'final signature is not yet deployed; exact known legacy 23-parameter signature is safely upgradeable and does not itself satisfy the final identity'
      else 'final signature is absent and the deployed overload state is not safely upgradeable'
    end as details
  from rpc_inventory
),
legacy_rpc_dependency_check as (
  select
    152 as sort_order,
    'SAVE_BILTY_WITH_ITEMS_LEGACY_DROP_DEPENDENCIES' as check_name,
    case when count(dependency_info.*) = 0 then 'PASS' else 'FAIL' end as status,
    case when count(dependency_info.*) = 0 then 'no database objects depend on the exact known legacy overload; DROP FUNCTION RESTRICT is safe'
      else string_agg(pg_describe_object(dependency_info.classid, dependency_info.objid, dependency_info.objsubid), ' | ' order by pg_describe_object(dependency_info.classid, dependency_info.objid, dependency_info.objsubid))
    end as details
  from pg_depend as dependency_info
  where dependency_info.refobjid = to_regprocedure('public.save_bilty_with_items(uuid,uuid,text,date,uuid,text,text,text,uuid,uuid,text,uuid,text,text,text,uuid,uuid,text,text,text,text,numeric,jsonb)')
    and dependency_info.deptype not in ('i', 'e')
),
blank_number_check as (
  select
    160 as sort_order,
    'LEGACY_BLANK_OR_NULL_BILTY_NUMBERS' as check_name,
    'PASS' as status,
    format('NULL booking_no rows=%s; blank-after-trim rows=%s. They are preserved and excluded from the partial unique index; the RPC rejects blank numbers for new/edited Biltys.', count(*) filter (where booking_no is null), count(*) filter (where booking_no is not null and btrim(booking_no) = '')) as details
  from public.bookings
),
existing_bilty_data_checks as (
  select
    165 as sort_order,
    'EXISTING_BILTY_ENUM_DATE_FINANCIAL_VALUES' as check_name,
    case when count(*) = 0 then 'PASS' else 'FAIL' end as status,
    format('rows incompatible with final Bilty checks=%s; ids=%s', count(*), coalesce(string_agg(booking.id::text, ', ' order by booking.id), '(none)')) as details
  from public.bookings as booking
  where
    ((to_jsonb(booking) ->> 'trip_type') is not null and (to_jsonb(booking) ->> 'trip_type') not in ('outbound', 'return', 'local'))
    or ((to_jsonb(booking) ->> 'freight_type') is not null and (to_jsonb(booking) ->> 'freight_type') not in ('paid', 'advance', 'to_pay'))
    or ((to_jsonb(booking) ->> 'bilty_type') is not null and (to_jsonb(booking) ->> 'bilty_type') not in ('self_vehicle', 'other_vehicle'))
    or ((to_jsonb(booking) ->> 'account_type') is not null and (to_jsonb(booking) ->> 'account_type') not in ('party_account', 'mt_account', 'other_account'))
    or (
      (to_jsonb(booking) ->> 'departure_date') is not null
      and (to_jsonb(booking) ->> 'arrival_date') is not null
      and (to_jsonb(booking) ->> 'arrival_date') < (to_jsonb(booking) ->> 'departure_date')
    )
    or exists (
      select 1
      from jsonb_each_text(to_jsonb(booking)) as field(field_name, field_value)
      where field.field_name in (
        'advance_vehicle', 'advance_bilty', 'advance_commission',
        'overweight_charges', 'mt_charges_receivable', 'mt_charges_payable',
        'party_commission', 'broker_commission', 'advance_brokerage',
        'other_income', 'deduction_adjustment'
      )
        and field.field_value like '-%'
    )

  union all

  select
    166,
    'EXISTING_BILTY_BROKER_REFERENCES',
    case when count(*) = 0 then 'PASS' else 'FAIL' end,
    format('orphan broker_id values=%s; booking ids=%s', count(*), coalesce(string_agg(booking.id::text, ', ' order by booking.id), '(none)'))
  from public.bookings as booking
  left join public.brokers as broker on broker.id::text = to_jsonb(booking) ->> 'broker_id'
  where (to_jsonb(booking) ->> 'broker_id') is not null and broker.id is null

  union all

  select
    167,
    'EXISTING_BILTY_VEHICLE_REFERENCES',
    case when count(*) = 0 then 'PASS' else 'FAIL' end,
    format('orphan vehicle_id values=%s; booking ids=%s', count(*), coalesce(string_agg(booking.id::text, ', ' order by booking.id), '(none)'))
  from public.bookings as booking
  left join public.vehicles as vehicle on vehicle.id::text = to_jsonb(booking) ->> 'vehicle_id'
  where (to_jsonb(booking) ->> 'vehicle_id') is not null and vehicle.id is null

  union all

  select
    168,
    'EXISTING_BILTY_LOCATION_REFERENCES_WITHOUT_MASTER',
    case
      when to_regclass('public.pakistan_locations') is null
       and count(*) filter (where (to_jsonb(booking) ->> 'from_location_id') is not null or (to_jsonb(booking) ->> 'to_location_id') is not null) > 0 then 'FAIL'
      when to_regclass('public.pakistan_locations') is not null
       and count(*) filter (where (to_jsonb(booking) ->> 'from_location_id') is not null or (to_jsonb(booking) ->> 'to_location_id') is not null) > 0
       and (
         not exists (select 1 from pg_constraint where conrelid = to_regclass('public.bookings') and conname = 'bookings_from_location_id_fkey' and convalidated)
         or not exists (select 1 from pg_constraint where conrelid = to_regclass('public.bookings') and conname = 'bookings_to_location_id_fkey' and convalidated)
       ) then 'FAIL'
      else 'PASS'
    end,
    format('location master exists=%s; bookings carrying location IDs=%s. Non-null partial location data requires already-validated final FKs so migration cannot fail while adding them.', to_regclass('public.pakistan_locations') is not null, count(*) filter (where (to_jsonb(booking) ->> 'from_location_id') is not null or (to_jsonb(booking) ->> 'to_location_id') is not null))
  from public.bookings as booking
),
group_compatibility_check as (
  select
    170 as sort_order,
    'BILTY_GROUP_COMPATIBILITY' as check_name,
    'PASS' as status,
    case
      when not exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'bookings' and column_name = 'bilty_group_id'
      ) then 'column absent; migration will add it and assign one UUID per legacy Booking'
      else format('column present; NULL group rows=%s (migration safely backfills these); non-NULL values are UUID-compatible', count(*) filter (where (to_jsonb(booking) ->> 'bilty_group_id') is null))
    end as details
  from public.bookings as booking
),
partial_inventory as (
  select 'relation=' || object_name as object_name
  from (values ('public.pakistan_locations'), ('public.bilty_items')) as objects(object_name)
  where to_regclass(object_name) is not null
  union all
  select 'column=public.bookings.' || expected.column_name
  from bilty_booking_columns as expected
  join information_schema.columns as actual
    on actual.table_schema = 'public' and actual.table_name = 'bookings' and actual.column_name = expected.column_name
  union all
  select 'function=public.save_bilty_with_items(...)' where exists (select 1 from rpc_inventory)
),
partial_state_check as (
  select
    180 as sort_order,
    'BILTY_FOUNDATION_DEPLOYMENT_STATE' as check_name,
    'PASS' as status,
    case when count(*) = 0 then 'Foundation is fully pending; compatible absent objects will be created'
      else 'Partial foundation detected. Presence alone is not a blocker; the detailed column/constraint/index/RLS/RPC checks above determine compatibility. Present objects: ' || string_agg(object_name, ' | ' order by object_name)
    end as details
  from partial_inventory
),
legacy_impact as (
  select
    190 as sort_order,
    'LEGACY_COMPATIBILITY_INPUT' as check_name,
    'PASS' as status,
    format(
      'bookings=%s; non-empty legacy goods=%s; non-empty location values=%s; distinct normalized locations=%s. Migration preserves original legacy columns.',
      (select count(*) from public.bookings),
      (select count(*) from public.bookings where goods_name is not null and btrim(goods_name) <> ''),
      count(*),
      count(distinct lower(btrim(location_name)))
    ) as details
  from (
    select from_city as location_name from public.bookings where from_city is not null and btrim(from_city) <> ''
    union all
    select to_city from public.bookings where to_city is not null and btrim(to_city) <> ''
  ) as locations
),
checks as (
  select * from relation_checks
  union all select * from column_checks
  union all select * from primary_key_check
  union all select * from fk_checks
  union all select * from data_integrity_checks
  union all select * from duplicate_number_check
  union all select * from party_trigger_check
  union all select * from additional_trigger_check
  union all select * from helper_checks
  union all select * from rls_checks
  union all select * from broker_contract_check
  union all select * from bilty_booking_column_checks
  union all select * from new_relation_column_checks
  union all select * from constraint_checks
  union all select * from index_checks
  union all select * from new_relation_rls_checks
  union all select * from rpc_deployment_state_check
  union all select * from rpc_final_signature_check
  union all select * from legacy_rpc_dependency_check
  union all select * from blank_number_check
  union all select * from existing_bilty_data_checks
  union all select * from group_compatibility_check
  union all select * from partial_state_check
  union all select * from legacy_impact
),
result as (
  select
    0 as sort_order,
    'OVERALL_BILTY_MIGRATION_PREFLIGHT' as check_name,
    case when count(*) filter (where status = 'FAIL') = 0 then 'PASS' else 'FAIL' end as status,
    format('PASS checks=%s; FAIL checks=%s. Apply only when FAIL checks=0.', count(*) filter (where status = 'PASS'), count(*) filter (where status = 'FAIL')) as details
  from checks

  union all

  select sort_order, check_name, status, details from checks
)
select check_name, status, details
from result
order by sort_order, check_name;
