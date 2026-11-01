begin;

do $$
declare
  required_relation text;
  duplicate_number record;
  actual_type text;
  unexpected_trigger record;
  bilty_rpc record;
  legacy_rpc_dependency record;
  bilty_rpc_count integer;
  legacy_bilty_rpc regprocedure := to_regprocedure(
    'public.save_bilty_with_items(uuid,uuid,text,date,uuid,text,text,text,uuid,uuid,text,uuid,text,text,text,uuid,uuid,text,text,text,text,numeric,jsonb)'
  );
  final_bilty_rpc regprocedure := to_regprocedure(
    'public.save_bilty_with_items(uuid,uuid,text,date,uuid,text,text,text,uuid,uuid,text,date,date,uuid,text,text,text,text,text,numeric,text,text,text,text,text,uuid,uuid,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,jsonb)'
  );
begin
  foreach required_relation in array array[
    'public.addas',
    'public.profiles',
    'public.bookings',
    'public.loadings',
    'public.parties',
    'public.brokers',
    'public.vehicles'
  ]
  loop
    if to_regclass(required_relation) is null then
      raise exception '% must exist before applying the Bilty foundation migration', required_relation;
    end if;
  end loop;

  select column_info.udt_name
  into actual_type
  from information_schema.columns as column_info
  where column_info.table_schema = 'public'
    and column_info.table_name = 'bookings'
    and column_info.column_name = 'id';
  if actual_type is distinct from 'uuid' then
    raise exception
      'Incompatible deployed schema: public.bookings.id must be uuid, found %',
      coalesce(actual_type, 'missing');
  end if;

  select column_info.udt_name
  into actual_type
  from information_schema.columns as column_info
  where column_info.table_schema = 'public'
    and column_info.table_name = 'bookings'
    and column_info.column_name = 'adda_id';
  if actual_type is distinct from 'uuid' then
    raise exception
      'Incompatible deployed schema: public.bookings.adda_id must be uuid, found %',
      coalesce(actual_type, 'missing');
  end if;

  select column_info.udt_name
  into actual_type
  from information_schema.columns as column_info
  where column_info.table_schema = 'public'
    and column_info.table_name = 'bookings'
    and column_info.column_name = 'booking_no';
  if actual_type is null or actual_type not in ('text', 'varchar') then
    raise exception
      'Incompatible deployed schema: public.bookings.booking_no must be text or varchar, found %',
      coalesce(actual_type, 'missing');
  end if;

  select column_info.udt_name
  into actual_type
  from information_schema.columns as column_info
  where column_info.table_schema = 'public'
    and column_info.table_name = 'loadings'
    and column_info.column_name = 'id';
  if actual_type is distinct from 'int8' then
    raise exception
      'Incompatible deployed schema: public.loadings.id must remain bigint/int8, found %',
      coalesce(actual_type, 'missing');
  end if;

  select column_info.udt_name
  into actual_type
  from information_schema.columns as column_info
  where column_info.table_schema = 'public'
    and column_info.table_name = 'loadings'
    and column_info.column_name = 'booking_id';
  if actual_type is distinct from 'uuid' then
    raise exception
      'Incompatible deployed schema: public.loadings.booking_id must be uuid, found %',
      coalesce(actual_type, 'missing');
  end if;

  if not exists (
    select 1
    from pg_constraint as constraint_info
    join pg_attribute as source_column
      on source_column.attrelid = constraint_info.conrelid
     and source_column.attnum = constraint_info.conkey[1]
    join pg_attribute as target_column
      on target_column.attrelid = constraint_info.confrelid
     and target_column.attnum = constraint_info.confkey[1]
    where constraint_info.contype = 'f'
      and constraint_info.conrelid = 'public.loadings'::regclass
      and constraint_info.confrelid = 'public.bookings'::regclass
      and source_column.attname = 'booking_id'
      and target_column.attname = 'id'
      and constraint_info.convalidated
  ) then
    raise exception
      'Incompatible deployed schema: a validated public.loadings.booking_id -> public.bookings.id foreign key is required';
  end if;

  select column_info.udt_name
  into actual_type
  from information_schema.columns as column_info
  where column_info.table_schema = 'public'
    and column_info.table_name = 'brokers'
    and column_info.column_name = 'id';
  if actual_type is distinct from 'uuid' then
    raise exception
      'Incompatible deployed schema: public.brokers.id must be uuid, found %',
      coalesce(actual_type, 'missing');
  end if;

  select column_info.udt_name
  into actual_type
  from information_schema.columns as column_info
  where column_info.table_schema = 'public'
    and column_info.table_name = 'parties'
    and column_info.column_name = 'id';
  if actual_type is distinct from 'uuid' then
    raise exception
      'Incompatible deployed schema: public.parties.id must be uuid, found %',
      coalesce(actual_type, 'missing');
  end if;

  select column_info.udt_name
  into actual_type
  from information_schema.columns as column_info
  where column_info.table_schema = 'public'
    and column_info.table_name = 'parties'
    and column_info.column_name = 'adda_id';
  if actual_type is distinct from 'uuid' then
    raise exception
      'Incompatible deployed schema: public.parties.adda_id must be uuid, found %',
      coalesce(actual_type, 'missing');
  end if;

  if not exists (
    select 1
    from pg_constraint as constraint_info
    join pg_attribute as source_column
      on source_column.attrelid = constraint_info.conrelid
     and source_column.attnum = constraint_info.conkey[1]
    join pg_attribute as target_column
      on target_column.attrelid = constraint_info.confrelid
     and target_column.attnum = constraint_info.confkey[1]
    where constraint_info.contype = 'f'
      and constraint_info.conrelid = 'public.bookings'::regclass
      and constraint_info.confrelid = 'public.parties'::regclass
      and source_column.attname = 'party_id'
      and target_column.attname = 'id'
      and constraint_info.convalidated
  ) then
    raise exception
      'Incompatible deployed schema: a validated public.bookings.party_id -> public.parties.id foreign key is required';
  end if;

  select column_info.udt_name
  into actual_type
  from information_schema.columns as column_info
  where column_info.table_schema = 'public'
    and column_info.table_name = 'vehicles'
    and column_info.column_name = 'id';
  if actual_type is distinct from 'uuid' then
    raise exception
      'Incompatible deployed schema: public.vehicles.id must be uuid, found %',
      coalesce(actual_type, 'missing');
  end if;

  if not exists (
    select 1
    from pg_trigger as trigger_info
    where trigger_info.tgrelid = 'public.bookings'::regclass
      and trigger_info.tgname = 'bookings_validate_party_adda'
      and not trigger_info.tgisinternal
      and trigger_info.tgenabled <> 'D'
  ) then
    raise exception
      'Incompatible deployed schema: enabled bookings_validate_party_adda trigger is required';
  end if;

  select
    trigger_info.tgname,
    pg_get_triggerdef(trigger_info.oid, true) as trigger_definition
  into unexpected_trigger
  from pg_trigger as trigger_info
  where trigger_info.tgrelid = 'public.bookings'::regclass
    and not trigger_info.tgisinternal
    and trigger_info.tgenabled <> 'D'
    and trigger_info.tgname not in (
      'bookings_validate_party_adda',
      'bookings_audit_log_trigger'
    )
  limit 1;

  if found then
    raise exception
      'Unknown enabled trigger % exists on public.bookings: %. Review it before applying the Bilty migration.',
      unexpected_trigger.tgname,
      unexpected_trigger.trigger_definition;
  end if;

  select column_info.udt_name
  into actual_type
  from information_schema.columns as column_info
  where column_info.table_schema = 'public'
    and column_info.table_name = 'vehicles'
    and column_info.column_name = 'adda_id';
  if actual_type is distinct from 'uuid' then
    raise exception
      'Incompatible deployed schema: public.vehicles.adda_id must be uuid, found %',
      coalesce(actual_type, 'missing');
  end if;

  select
    booking.adda_id,
    lower(btrim(booking.booking_no)) as bilty_number,
    count(*) as duplicate_count
  into duplicate_number
  from public.bookings as booking
  where booking.booking_no is not null
    and btrim(booking.booking_no) <> ''
  group by booking.adda_id, lower(btrim(booking.booking_no))
  having count(*) > 1
  limit 1;

  if found then
    raise exception
      'Duplicate Bilty number % exists in Adda %. Resolve duplicates before applying this migration.',
      duplicate_number.bilty_number,
      duplicate_number.adda_id;
  end if;

  select count(*)
  into bilty_rpc_count
  from pg_proc as procedure_info
  join pg_namespace as namespace_info
    on namespace_info.oid = procedure_info.pronamespace
  where namespace_info.nspname = 'public'
    and procedure_info.proname = 'save_bilty_with_items';

  if bilty_rpc_count > 1 then
    raise exception
      'Conflicting public.save_bilty_with_items overloads exist (% found). Expected none, only the known legacy signature, or only the final signature.',
      bilty_rpc_count;
  end if;

  select
    procedure_info.oid,
    pg_get_function_identity_arguments(procedure_info.oid) as identity_arguments,
    pg_get_function_result(procedure_info.oid) as result_type,
    procedure_info.prosecdef as security_definer,
    language_info.lanname as language_name
  into bilty_rpc
  from pg_proc as procedure_info
  join pg_namespace as namespace_info
    on namespace_info.oid = procedure_info.pronamespace
  join pg_language as language_info
    on language_info.oid = procedure_info.prolang
  where namespace_info.nspname = 'public'
    and procedure_info.proname = 'save_bilty_with_items'
  limit 1;

  if found then
    if bilty_rpc.oid is distinct from legacy_bilty_rpc::oid
       and bilty_rpc.oid is distinct from final_bilty_rpc::oid then
      raise exception
        'Unexpected public.save_bilty_with_items signature: (%). Expected the known legacy 23-parameter signature or the final 45-parameter signature.',
        bilty_rpc.identity_arguments;
    end if;

    if bilty_rpc.result_type <> 'uuid'
       or bilty_rpc.security_definer
       or bilty_rpc.language_name <> 'plpgsql' then
      raise exception
        'Unsafe public.save_bilty_with_items contract: signature=(%), return=%, security_definer=%, language=%. Expected uuid, SECURITY INVOKER, plpgsql.',
        bilty_rpc.identity_arguments,
        bilty_rpc.result_type,
        bilty_rpc.security_definer,
        bilty_rpc.language_name;
    end if;
  end if;

  if legacy_bilty_rpc is not null then
    select
      pg_describe_object(
        dependency_info.classid,
        dependency_info.objid,
        dependency_info.objsubid
      ) as dependent_object
    into legacy_rpc_dependency
    from pg_depend as dependency_info
    where dependency_info.refobjid = legacy_bilty_rpc::oid
      and dependency_info.deptype not in ('i', 'e')
    limit 1;

    if found then
      raise exception
        'Cannot safely replace the legacy public.save_bilty_with_items overload because % depends on it.',
        legacy_rpc_dependency.dependent_object;
    end if;
  end if;
end;
$$;

-- The deployed bookings_validate_party_adda trigger enforces Party/Adda integrity.
-- The deployed bookings_audit_log_trigger is also a known legitimate trigger and
-- remains enabled; Bilty compatibility updates may therefore create normal audit
-- records. The preflight aborts for any other enabled, non-internal trigger so an
-- unknown trigger cannot introduce unreviewed operational or financial effects.
-- Brokers remain a global master under the current deployed contract (no adda_id
-- column and no Broker RLS). This migration does not change Broker access or RLS.
-- It also preserves the bigint public.loadings.id contract and the existing UUID
-- loadings.booking_id -> bookings.id relationship. This migration does
-- not create Loading, Cashbook, Voucher, Receipt, Diesel, Expense, or other
-- financial records, and it intentionally leaves all legacy operational tables
-- untouched.

create table if not exists public.pakistan_locations (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid null references public.pakistan_locations(id) on delete restrict,
  location_type text not null,
  name text not null,
  normalized_name text generated always as (lower(btrim(name))) stored,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pakistan_locations_type_check
    check (location_type in ('province', 'district', 'tehsil', 'city')),
  constraint pakistan_locations_name_check check (btrim(name) <> '')
);

create unique index if not exists pakistan_locations_hierarchy_name_uidx
  on public.pakistan_locations (
    coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid),
    location_type,
    normalized_name
  );

create index if not exists pakistan_locations_search_idx
  on public.pakistan_locations (normalized_name text_pattern_ops)
  where is_active = true;

alter table public.pakistan_locations enable row level security;

drop policy if exists pakistan_locations_authenticated_read on public.pakistan_locations;
create policy pakistan_locations_authenticated_read
on public.pakistan_locations
for select
to authenticated
using (is_active = true or public.is_super_admin());

drop policy if exists pakistan_locations_super_admin_manage on public.pakistan_locations;
create policy pakistan_locations_super_admin_manage
on public.pakistan_locations
for all
to authenticated
using (public.is_super_admin())
with check (public.is_super_admin());

alter table public.bookings
  add column if not exists bilty_group_id uuid,
  add column if not exists trip_type text,
  add column if not exists freight_type text,
  add column if not exists bilty_type text,
  add column if not exists broker_id uuid,
  add column if not exists reference_no text,
  add column if not exists departure_date date,
  add column if not exists arrival_date date,
  add column if not exists vehicle_id uuid,
  add column if not exists external_vehicle_no text,
  add column if not exists external_vehicle_type text,
  add column if not exists external_owner_name text,
  add column if not exists container_no text,
  add column if not exists container_size text,
  add column if not exists container_weight numeric,
  add column if not exists container_serial text,
  add column if not exists container_port text,
  add column if not exists clearing_agent text,
  add column if not exists shipping_line text,
  add column if not exists container_cargo text,
  add column if not exists advance_vehicle numeric not null default 0,
  add column if not exists advance_bilty numeric not null default 0,
  add column if not exists advance_commission numeric not null default 0,
  add column if not exists overweight_charges numeric not null default 0,
  add column if not exists mt_charges_receivable numeric not null default 0,
  add column if not exists mt_charges_payable numeric not null default 0,
  add column if not exists party_commission numeric not null default 0,
  add column if not exists broker_commission numeric not null default 0,
  add column if not exists advance_brokerage numeric not null default 0,
  add column if not exists other_income numeric not null default 0,
  add column if not exists deduction_adjustment numeric not null default 0,
  add column if not exists account_type text,
  add column if not exists from_location_id uuid,
  add column if not exists to_location_id uuid;

update public.bookings
set bilty_group_id = gen_random_uuid()
where bilty_group_id is null;

alter table public.bookings
  alter column bilty_group_id set default gen_random_uuid(),
  alter column bilty_group_id set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.bookings'::regclass
      and conname = 'bookings_trip_type_check'
  ) then
    alter table public.bookings add constraint bookings_trip_type_check
      check (trip_type is null or trip_type in ('outbound', 'return', 'local'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.bookings'::regclass
      and conname = 'bookings_bilty_dates_check'
  ) then
    alter table public.bookings add constraint bookings_bilty_dates_check
      check (arrival_date is null or departure_date is null or arrival_date >= departure_date);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.bookings'::regclass
      and conname = 'bookings_bilty_account_type_check'
  ) then
    alter table public.bookings add constraint bookings_bilty_account_type_check
      check (account_type is null or account_type in ('party_account', 'mt_account', 'other_account'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.bookings'::regclass
      and conname = 'bookings_bilty_financial_values_check'
  ) then
    alter table public.bookings add constraint bookings_bilty_financial_values_check
      check (
        advance_vehicle >= 0 and advance_bilty >= 0 and advance_commission >= 0
        and overweight_charges >= 0 and mt_charges_receivable >= 0
        and mt_charges_payable >= 0 and party_commission >= 0
        and broker_commission >= 0 and advance_brokerage >= 0
        and other_income >= 0 and deduction_adjustment >= 0
        and (container_weight is null or container_weight >= 0)
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.bookings'::regclass
      and conname = 'bookings_freight_type_check'
  ) then
    alter table public.bookings add constraint bookings_freight_type_check
      check (freight_type is null or freight_type in ('paid', 'advance', 'to_pay'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.bookings'::regclass
      and conname = 'bookings_bilty_type_check'
  ) then
    alter table public.bookings add constraint bookings_bilty_type_check
      check (bilty_type is null or bilty_type in ('self_vehicle', 'other_vehicle'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.bookings'::regclass
      and conname = 'bookings_broker_id_fkey'
  ) then
    alter table public.bookings add constraint bookings_broker_id_fkey
      foreign key (broker_id) references public.brokers(id) on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.bookings'::regclass
      and conname = 'bookings_vehicle_id_fkey'
  ) then
    alter table public.bookings add constraint bookings_vehicle_id_fkey
      foreign key (vehicle_id) references public.vehicles(id) on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.bookings'::regclass
      and conname = 'bookings_from_location_id_fkey'
  ) then
    alter table public.bookings add constraint bookings_from_location_id_fkey
      foreign key (from_location_id) references public.pakistan_locations(id) on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.bookings'::regclass
      and conname = 'bookings_to_location_id_fkey'
  ) then
    alter table public.bookings add constraint bookings_to_location_id_fkey
      foreign key (to_location_id) references public.pakistan_locations(id) on delete restrict;
  end if;
end;
$$;

create unique index if not exists bookings_adda_bilty_number_uidx
  on public.bookings (adda_id, lower(btrim(booking_no)))
  where booking_no is not null and btrim(booking_no) <> '';

create index if not exists bookings_adda_group_idx
  on public.bookings (adda_id, bilty_group_id);
create index if not exists bookings_broker_id_idx on public.bookings (broker_id);
create index if not exists bookings_vehicle_id_idx on public.bookings (vehicle_id);
create index if not exists bookings_from_location_id_idx on public.bookings (from_location_id);
create index if not exists bookings_to_location_id_idx on public.bookings (to_location_id);

with legacy_values as (
  select btrim(booking.from_city) as name
  from public.bookings as booking
  where booking.from_city is not null and btrim(booking.from_city) <> ''

  union all

  select btrim(booking.to_city) as name
  from public.bookings as booking
  where booking.to_city is not null and btrim(booking.to_city) <> ''
),
normalized_legacy_locations as (
  select
    lower(legacy.name) as normalized_name,
    min(legacy.name) as display_name
  from legacy_values as legacy
  group by lower(legacy.name)
)
insert into public.pakistan_locations (location_type, name)
select 'city', legacy.display_name
from normalized_legacy_locations as legacy
where not exists (
  select 1
  from public.pakistan_locations as location
  where location.parent_id is null
    and location.location_type = 'city'
    and location.normalized_name = legacy.normalized_name
);

update public.bookings as booking
set from_location_id = location.id
from public.pakistan_locations as location
where booking.from_location_id is null
  and location.parent_id is null
  and location.location_type = 'city'
  and location.normalized_name = lower(btrim(booking.from_city));

update public.bookings as booking
set to_location_id = location.id
from public.pakistan_locations as location
where booking.to_location_id is null
  and location.parent_id is null
  and location.location_type = 'city'
  and location.normalized_name = lower(btrim(booking.to_city));

create table if not exists public.bilty_items (
  id uuid primary key default gen_random_uuid(),
  bilty_id uuid not null references public.bookings(id) on delete cascade,
  line_no integer not null default 1,
  goods_name text not null,
  quantity numeric not null,
  weight numeric null,
  unit text not null,
  remarks text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint bilty_items_line_no_check check (line_no > 0),
  constraint bilty_items_goods_name_check check (btrim(goods_name) <> ''),
  constraint bilty_items_quantity_check check (quantity > 0 and quantity <= 1000000000),
  constraint bilty_items_weight_check check (weight is null or (weight >= 0 and weight <= 1000000000)),
  constraint bilty_items_unit_check check (btrim(unit) <> ''),
  constraint bilty_items_bilty_line_key unique (bilty_id, line_no)
);

create index if not exists bilty_items_bilty_id_idx
  on public.bilty_items (bilty_id, line_no);

alter table public.bilty_items enable row level security;

drop policy if exists bilty_items_tenant_read on public.bilty_items;
create policy bilty_items_tenant_read
on public.bilty_items
for select
to authenticated
using (
  exists (
    select 1 from public.bookings as booking
    where booking.id = bilty_items.bilty_id
      and (
        public.is_super_admin()
        or booking.adda_id = public.current_user_adda_id()
      )
  )
);

drop policy if exists bilty_items_tenant_insert on public.bilty_items;
create policy bilty_items_tenant_insert
on public.bilty_items
for insert
to authenticated
with check (
  exists (
    select 1 from public.bookings as booking
    where booking.id = bilty_items.bilty_id
      and (
        public.is_super_admin()
        or booking.adda_id = public.current_user_adda_id()
      )
  )
);

drop policy if exists bilty_items_tenant_update on public.bilty_items;
create policy bilty_items_tenant_update
on public.bilty_items
for update
to authenticated
using (
  exists (
    select 1 from public.bookings as booking
    where booking.id = bilty_items.bilty_id
      and (
        public.is_super_admin()
        or booking.adda_id = public.current_user_adda_id()
      )
  )
)
with check (
  exists (
    select 1 from public.bookings as booking
    where booking.id = bilty_items.bilty_id
      and (
        public.is_super_admin()
        or booking.adda_id = public.current_user_adda_id()
      )
  )
);

drop policy if exists bilty_items_tenant_delete on public.bilty_items;
create policy bilty_items_tenant_delete
on public.bilty_items
for delete
to authenticated
using (
  exists (
    select 1 from public.bookings as booking
    where booking.id = bilty_items.bilty_id
      and (
        public.is_super_admin()
        or booking.adda_id = public.current_user_adda_id()
      )
  )
);

insert into public.bilty_items (
  bilty_id,
  line_no,
  goods_name,
  quantity,
  weight,
  unit,
  remarks
)
select
  booking.id,
  1,
  btrim(booking.goods_name),
  greatest(coalesce(booking.quantity, 1), 0.000001),
  case when booking.weight is null then null else greatest(booking.weight, 0) end,
  'unit',
  null
from public.bookings as booking
where booking.goods_name is not null
  and btrim(booking.goods_name) <> ''
  and not exists (
    select 1 from public.bilty_items as item where item.bilty_id = booking.id
  );

-- PostgreSQL identifies functions by name plus input argument types. The known
-- Phase 1 function has a shorter identity and cannot be upgraded with CREATE OR
-- REPLACE. Drop only that reviewed overload (RESTRICT is the default); any
-- dependency or unexpected overload causes this transaction to fail safely.
drop function if exists public.save_bilty_with_items(
  uuid, uuid, text, date, uuid, text, text, text, uuid, uuid, text, uuid,
  text, text, text, uuid, uuid, text, text, text, text, numeric, jsonb
);

create or replace function public.save_bilty_with_items(
  p_bilty_id uuid,
  p_adda_id uuid,
  p_booking_no text,
  p_booking_date date,
  p_group_id uuid,
  p_trip_type text,
  p_freight_type text,
  p_bilty_type text,
  p_party_id uuid,
  p_broker_id uuid,
  p_reference_no text,
  p_departure_date date,
  p_arrival_date date,
  p_vehicle_id uuid,
  p_external_vehicle_no text,
  p_external_vehicle_type text,
  p_external_owner_name text,
  p_container_no text,
  p_container_size text,
  p_container_weight numeric,
  p_container_serial text,
  p_container_port text,
  p_clearing_agent text,
  p_shipping_line text,
  p_container_cargo text,
  p_from_location_id uuid,
  p_to_location_id uuid,
  p_sender_name text,
  p_sender_phone text,
  p_receiver_name text,
  p_receiver_phone text,
  p_freight numeric,
  p_advance_vehicle numeric,
  p_advance_bilty numeric,
  p_advance_commission numeric,
  p_overweight_charges numeric,
  p_mt_charges_receivable numeric,
  p_mt_charges_payable numeric,
  p_party_commission numeric,
  p_broker_commission numeric,
  p_advance_brokerage numeric,
  p_other_income numeric,
  p_deduction_adjustment numeric,
  p_account_type text,
  p_items jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  caller_role text;
  caller_adda_id uuid;
  caller_active boolean;
  existing_adda_id uuid;
  saved_id uuid;
  resolved_group_id uuid := coalesce(p_group_id, gen_random_uuid());
  item jsonb;
  first_goods_name text;
  total_quantity numeric;
  total_weight numeric;
  from_location_name text;
  to_location_name text;
begin
  select profile.role, profile.adda_id, profile.is_active
  into caller_role, caller_adda_id, caller_active
  from public.profiles as profile
  where profile.id = auth.uid();

  if caller_active is distinct from true
    or caller_role not in ('super_admin', 'adda_admin', 'operator') then
    raise exception using errcode = '42501', message = 'Bilty access denied';
  end if;

  if caller_role <> 'super_admin' and caller_adda_id is distinct from p_adda_id then
    raise exception using errcode = '42501', message = 'Bilty Adda access denied';
  end if;

  if p_adda_id is null or not exists (select 1 from public.addas where id = p_adda_id) then
    raise exception using errcode = '23514', message = 'A valid Adda is required';
  end if;

  if nullif(btrim(p_booking_no), '') is null or p_booking_date is null then
    raise exception using errcode = '23514', message = 'Bilty number and date are required';
  end if;

  if p_trip_type not in ('outbound', 'return', 'local')
    or p_freight_type not in ('paid', 'advance', 'to_pay')
    or p_bilty_type not in ('self_vehicle', 'other_vehicle') then
    raise exception using errcode = '23514', message = 'Invalid Bilty type selection';
  end if;

  if p_freight is null or p_freight < 0 then
    raise exception using errcode = '23514', message = 'Freight must be zero or greater';
  end if;

  if p_arrival_date is not null and p_departure_date is not null
    and p_arrival_date < p_departure_date then
    raise exception using errcode = '23514', message = 'Arrival date cannot be earlier than departure date';
  end if;

  if p_account_type is not null
    and p_account_type not in ('party_account', 'mt_account', 'other_account') then
    raise exception using errcode = '23514', message = 'Invalid Bilty account classification';
  end if;

  if coalesce(p_advance_vehicle, 0) < 0
    or coalesce(p_advance_bilty, 0) < 0
    or coalesce(p_advance_commission, 0) < 0
    or coalesce(p_overweight_charges, 0) < 0
    or coalesce(p_mt_charges_receivable, 0) < 0
    or coalesce(p_mt_charges_payable, 0) < 0
    or coalesce(p_party_commission, 0) < 0
    or coalesce(p_broker_commission, 0) < 0
    or coalesce(p_advance_brokerage, 0) < 0
    or coalesce(p_other_income, 0) < 0
    or coalesce(p_deduction_adjustment, 0) < 0
    or coalesce(p_container_weight, 0) < 0 then
    raise exception using errcode = '23514', message = 'Bilty financial values cannot be negative';
  end if;

  if p_party_id is not null and not exists (
    select 1 from public.parties
    where id = p_party_id and adda_id = p_adda_id and is_active = true
  ) then
    raise exception using errcode = '23514', message = 'Selected Party is not available for this Adda';
  end if;

  if p_group_id is not null and not exists (
    select 1 from public.bookings
    where adda_id = p_adda_id and bilty_group_id = p_group_id
  ) then
    raise exception using errcode = '23514', message = 'Selected movement group is not available for this Adda';
  end if;

  if p_broker_id is not null and not exists (
    select 1 from public.brokers where id = p_broker_id
  ) then
    raise exception using errcode = '23514', message = 'Selected Broker is not available';
  end if;

  if p_bilty_type = 'self_vehicle' then
    if p_vehicle_id is null or not exists (
      select 1 from public.vehicles where id = p_vehicle_id and adda_id = p_adda_id
    ) then
      raise exception using errcode = '23514', message = 'Select a vehicle belonging to this Adda';
    end if;
  elsif nullif(btrim(p_external_vehicle_no), '') is null then
    raise exception using errcode = '23514', message = 'Other vehicle number is required';
  end if;

  select location.name into from_location_name
  from public.pakistan_locations as location
  where location.id = p_from_location_id and location.is_active = true;
  select location.name into to_location_name
  from public.pakistan_locations as location
  where location.id = p_to_location_id and location.is_active = true;

  if from_location_name is null or to_location_name is null then
    raise exception using errcode = '23514', message = 'Select valid From and To locations';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception using errcode = '23514', message = 'At least one Bilty item is required';
  end if;

  for item in select value from jsonb_array_elements(p_items)
  loop
    if nullif(btrim(item->>'goods_name'), '') is null
      or nullif(btrim(item->>'unit'), '') is null
      or coalesce((item->>'quantity')::numeric, 0) <= 0
      or coalesce((item->>'weight')::numeric, 0) < 0 then
      raise exception using errcode = '23514', message = 'Invalid Bilty item';
    end if;
  end loop;

  select
    min(value->>'goods_name'),
    sum((value->>'quantity')::numeric),
    sum(coalesce((value->>'weight')::numeric, 0))
  into first_goods_name, total_quantity, total_weight
  from jsonb_array_elements(p_items);

  if p_bilty_id is not null then
    select booking.adda_id into existing_adda_id
    from public.bookings as booking
    where booking.id = p_bilty_id;

    if existing_adda_id is null then
      raise exception using errcode = 'P0002', message = 'Bilty not found';
    end if;
    if existing_adda_id is distinct from p_adda_id then
      raise exception using errcode = '23514', message = 'Bilty Adda cannot be changed';
    end if;

    update public.bookings
    set booking_no = btrim(p_booking_no),
        booking_date = p_booking_date,
        bilty_group_id = resolved_group_id,
        trip_type = p_trip_type,
        freight_type = p_freight_type,
        bilty_type = p_bilty_type,
        party_id = p_party_id,
        broker_id = p_broker_id,
        reference_no = nullif(btrim(p_reference_no), ''),
        departure_date = p_departure_date,
        arrival_date = p_arrival_date,
        vehicle_id = case when p_bilty_type = 'self_vehicle' then p_vehicle_id else null end,
        external_vehicle_no = case when p_bilty_type = 'other_vehicle' then nullif(btrim(p_external_vehicle_no), '') else null end,
        external_vehicle_type = case when p_bilty_type = 'other_vehicle' then nullif(btrim(p_external_vehicle_type), '') else null end,
        external_owner_name = case when p_bilty_type = 'other_vehicle' then nullif(btrim(p_external_owner_name), '') else null end,
        container_no = nullif(btrim(p_container_no), ''),
        container_size = nullif(btrim(p_container_size), ''),
        container_weight = p_container_weight,
        container_serial = nullif(btrim(p_container_serial), ''),
        container_port = nullif(btrim(p_container_port), ''),
        clearing_agent = nullif(btrim(p_clearing_agent), ''),
        shipping_line = nullif(btrim(p_shipping_line), ''),
        container_cargo = nullif(btrim(p_container_cargo), ''),
        from_location_id = p_from_location_id,
        to_location_id = p_to_location_id,
        from_city = from_location_name,
        to_city = to_location_name,
        sender_name = btrim(coalesce(p_sender_name, '')),
        sender_phone = btrim(coalesce(p_sender_phone, '')),
        receiver_name = btrim(coalesce(p_receiver_name, '')),
        receiver_phone = btrim(coalesce(p_receiver_phone, '')),
        goods_name = first_goods_name,
        quantity = total_quantity,
        weight = total_weight,
        freight = p_freight,
        advance_vehicle = coalesce(p_advance_vehicle, 0),
        advance_bilty = coalesce(p_advance_bilty, 0),
        advance_commission = coalesce(p_advance_commission, 0),
        overweight_charges = coalesce(p_overweight_charges, 0),
        mt_charges_receivable = coalesce(p_mt_charges_receivable, 0),
        mt_charges_payable = coalesce(p_mt_charges_payable, 0),
        party_commission = coalesce(p_party_commission, 0),
        broker_commission = coalesce(p_broker_commission, 0),
        advance_brokerage = coalesce(p_advance_brokerage, 0),
        other_income = coalesce(p_other_income, 0),
        deduction_adjustment = coalesce(p_deduction_adjustment, 0),
        account_type = p_account_type
    where id = p_bilty_id
    returning id into saved_id;
  else
    insert into public.bookings (
      adda_id, party_id, booking_no, booking_date, sender_name, sender_phone,
      receiver_name, receiver_phone, from_city, to_city, goods_name, quantity,
      weight, freight, status, bilty_group_id, trip_type, freight_type,
      bilty_type, broker_id, reference_no, vehicle_id, external_vehicle_no,
      external_vehicle_type, external_owner_name, departure_date, arrival_date,
      container_no, container_size, container_weight, container_serial,
      container_port, clearing_agent, shipping_line, container_cargo,
      advance_vehicle, advance_bilty, advance_commission, overweight_charges,
      mt_charges_receivable, mt_charges_payable, party_commission,
      broker_commission, advance_brokerage, other_income, deduction_adjustment,
      account_type, from_location_id, to_location_id
    ) values (
      p_adda_id, p_party_id, btrim(p_booking_no), p_booking_date,
      btrim(coalesce(p_sender_name, '')), btrim(coalesce(p_sender_phone, '')),
      btrim(coalesce(p_receiver_name, '')), btrim(coalesce(p_receiver_phone, '')),
      from_location_name, to_location_name, first_goods_name, total_quantity,
      total_weight, p_freight, 'Booked', resolved_group_id, p_trip_type,
      p_freight_type, p_bilty_type, p_broker_id, nullif(btrim(p_reference_no), ''),
      case when p_bilty_type = 'self_vehicle' then p_vehicle_id else null end,
      case when p_bilty_type = 'other_vehicle' then nullif(btrim(p_external_vehicle_no), '') else null end,
      case when p_bilty_type = 'other_vehicle' then nullif(btrim(p_external_vehicle_type), '') else null end,
      case when p_bilty_type = 'other_vehicle' then nullif(btrim(p_external_owner_name), '') else null end,
      p_departure_date, p_arrival_date,
      nullif(btrim(p_container_no), ''), nullif(btrim(p_container_size), ''),
      p_container_weight, nullif(btrim(p_container_serial), ''),
      nullif(btrim(p_container_port), ''), nullif(btrim(p_clearing_agent), ''),
      nullif(btrim(p_shipping_line), ''), nullif(btrim(p_container_cargo), ''),
      coalesce(p_advance_vehicle, 0), coalesce(p_advance_bilty, 0),
      coalesce(p_advance_commission, 0), coalesce(p_overweight_charges, 0),
      coalesce(p_mt_charges_receivable, 0), coalesce(p_mt_charges_payable, 0),
      coalesce(p_party_commission, 0), coalesce(p_broker_commission, 0),
      coalesce(p_advance_brokerage, 0), coalesce(p_other_income, 0),
      coalesce(p_deduction_adjustment, 0), p_account_type,
      p_from_location_id, p_to_location_id
    ) returning id into saved_id;
  end if;

  delete from public.bilty_items where bilty_id = saved_id;

  insert into public.bilty_items (
    bilty_id, line_no, goods_name, quantity, weight, unit, remarks
  )
  select
    saved_id,
    ordinality::integer,
    btrim(value->>'goods_name'),
    (value->>'quantity')::numeric,
    nullif(value->>'weight', '')::numeric,
    btrim(value->>'unit'),
    nullif(btrim(value->>'remarks'), '')
  from jsonb_array_elements(p_items) with ordinality as item(value, ordinality);

  return saved_id;
end;
$$;

revoke all on function public.save_bilty_with_items(
  uuid, uuid, text, date, uuid, text, text, text, uuid, uuid, text, date,
  date, uuid, text, text, text, text, text, numeric, text, text, text, text,
  text, uuid, uuid, text, text, text, text, numeric, numeric, numeric, numeric,
  numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, text,
  jsonb
) from public;
grant execute on function public.save_bilty_with_items(
  uuid, uuid, text, date, uuid, text, text, text, uuid, uuid, text, date,
  date, uuid, text, text, text, text, text, numeric, text, text, text, text,
  text, uuid, uuid, text, text, text, text, numeric, numeric, numeric, numeric,
  numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, text,
  jsonb
) to authenticated;

commit;
