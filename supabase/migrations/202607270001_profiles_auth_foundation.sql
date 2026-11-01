begin;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role text not null,
  adda_id uuid references public.addas(id),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles
  add column if not exists id uuid,
  add column if not exists full_name text,
  add column if not exists role text,
  add column if not exists adda_id uuid,
  add column if not exists is_active boolean not null default true,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

update public.profiles
set
  is_active = coalesce(is_active, true),
  created_at = coalesce(created_at, now()),
  updated_at = coalesce(updated_at, created_at, now())
where is_active is null
   or created_at is null
   or updated_at is null;

do $$
begin
  if exists (
    select 1
    from public.profiles
    where id is null
  ) then
    raise exception
      'profiles.id contains null values; resolve them before applying the authentication foundation migration';
  end if;

  if exists (
    select 1
    from public.profiles
    where role is null
  ) then
    raise exception
      'profiles.role contains null values; resolve them before applying the authentication foundation migration';
  end if;

  if exists (
    select 1
    from public.profiles
    where role not in ('super_admin', 'adda_admin', 'operator')
  ) then
    raise exception
      'profiles.role contains unsupported values; resolve them before applying the authentication foundation migration';
  end if;

  if exists (
    select 1
    from public.profiles
    where role in ('adda_admin', 'operator')
      and adda_id is null
  ) then
    raise exception
      'Adda Admin and Operator profiles require an adda_id before applying the authentication foundation migration';
  end if;
end;
$$;

alter table public.profiles
  alter column role set not null,
  alter column is_active set default true,
  alter column is_active set not null,
  alter column created_at set default now(),
  alter column created_at set not null,
  alter column updated_at set default now(),
  alter column updated_at set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and contype = 'p'
  ) then
    alter table public.profiles
      add constraint profiles_pkey primary key (id);
  end if;

  if not exists (
    select 1
    from pg_constraint as constraint_record
    where constraint_record.conrelid = 'public.profiles'::regclass
      and constraint_record.confrelid = 'auth.users'::regclass
      and constraint_record.contype = 'f'
      and constraint_record.conkey = array[
        (
          select attribute.attnum
          from pg_attribute as attribute
          where attribute.attrelid = 'public.profiles'::regclass
            and attribute.attname = 'id'
            and not attribute.attisdropped
        )
      ]
      and constraint_record.confkey = array[
        (
          select attribute.attnum
          from pg_attribute as attribute
          where attribute.attrelid = 'auth.users'::regclass
            and attribute.attname = 'id'
            and not attribute.attisdropped
        )
      ]
      and constraint_record.confdeltype = 'c'
  ) then
    alter table public.profiles
      add constraint profiles_id_auth_users_fkey
      foreign key (id) references auth.users(id) on delete cascade;
  end if;

  alter table public.profiles
    drop constraint if exists profiles_adda_id_fkey;

  alter table public.profiles
    add constraint profiles_adda_id_fkey
    foreign key (adda_id)
    references public.addas(id)
    on delete restrict;
end;
$$;

alter table public.profiles
  drop constraint if exists profiles_role_allowed_check,
  drop constraint if exists profiles_role_adda_assignment_check;

alter table public.profiles
  add constraint profiles_role_allowed_check
  check (role in ('super_admin', 'adda_admin', 'operator')),
  add constraint profiles_role_adda_assignment_check
  check (
    role = 'super_admin'
    or (
      role in ('adda_admin', 'operator')
      and adda_id is not null
    )
  );

create or replace function public.set_profiles_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;

create trigger profiles_set_updated_at
before update on public.profiles
for each row
execute function public.set_profiles_updated_at();

create or replace function public.current_user_role()
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select profile.role
  from public.profiles as profile
  where profile.id = auth.uid()
    and profile.is_active = true
  limit 1;
$$;

create or replace function public.current_user_adda_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select profile.adda_id
  from public.profiles as profile
  where profile.id = auth.uid()
    and profile.is_active = true
  limit 1;
$$;

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(public.current_user_role() = 'super_admin', false);
$$;

revoke all on function public.current_user_role() from public;
revoke all on function public.current_user_adda_id() from public;
revoke all on function public.is_super_admin() from public;
revoke all on function public.current_user_role() from anon;
revoke all on function public.current_user_adda_id() from anon;
revoke all on function public.is_super_admin() from anon;

grant execute on function public.current_user_role() to authenticated;
grant execute on function public.current_user_adda_id() to authenticated;
grant execute on function public.is_super_admin() to authenticated;

alter table public.profiles enable row level security;
alter table public.addas enable row level security;

do $$
declare
  policy_record record;
begin
  for policy_record in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('profiles', 'addas')
  loop
    execute format(
      'drop policy if exists %I on %I.%I',
      policy_record.policyname,
      policy_record.schemaname,
      policy_record.tablename
    );
  end loop;
end;
$$;

create policy profiles_select_own
on public.profiles
for select
to authenticated
using (id = auth.uid());

create policy profiles_select_super_admin
on public.profiles
for select
to authenticated
using (public.is_super_admin());

create policy profiles_select_same_adda_for_adda_admin
on public.profiles
for select
to authenticated
using (
  public.current_user_role() = 'adda_admin'
  and adda_id = public.current_user_adda_id()
);

revoke all on public.profiles from anon;
revoke insert, update, delete on public.profiles from authenticated;
grant select on public.profiles to authenticated;

create policy addas_select_authorized
on public.addas
for select
to authenticated
using (
  public.is_super_admin()
  or id = public.current_user_adda_id()
);

create policy addas_insert_super_admin
on public.addas
for insert
to authenticated
with check (public.is_super_admin());

create policy addas_update_super_admin
on public.addas
for update
to authenticated
using (public.is_super_admin())
with check (public.is_super_admin());

create policy addas_delete_super_admin
on public.addas
for delete
to authenticated
using (public.is_super_admin());

revoke all on public.addas from anon;
grant select, insert, update, delete on public.addas to authenticated;

commit;
