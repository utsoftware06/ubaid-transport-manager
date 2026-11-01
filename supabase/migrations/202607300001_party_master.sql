begin;

create table if not exists public.parties (
  id uuid primary key default gen_random_uuid(),
  adda_id uuid not null references public.addas(id) on delete restrict,
  name text not null,
  phone text,
  city text,
  address text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint parties_name_not_blank_check check (length(btrim(name)) > 0)
);

create index if not exists parties_adda_id_idx
  on public.parties (adda_id);

create index if not exists parties_adda_active_idx
  on public.parties (adda_id, is_active);

create index if not exists parties_adda_city_idx
  on public.parties (adda_id, city);

create or replace function public.set_parties_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists parties_set_updated_at on public.parties;

create trigger parties_set_updated_at
before update on public.parties
for each row
execute function public.set_parties_updated_at();

alter table public.parties enable row level security;

drop policy if exists parties_select_authorized on public.parties;
create policy parties_select_authorized
on public.parties
for select
to authenticated
using (
  public.is_super_admin()
  or adda_id = public.current_user_adda_id()
);

drop policy if exists parties_insert_authorized on public.parties;
create policy parties_insert_authorized
on public.parties
for insert
to authenticated
with check (
  public.is_super_admin()
  or adda_id = public.current_user_adda_id()
);

drop policy if exists parties_update_authorized on public.parties;
create policy parties_update_authorized
on public.parties
for update
to authenticated
using (
  public.is_super_admin()
  or adda_id = public.current_user_adda_id()
)
with check (
  public.is_super_admin()
  or adda_id = public.current_user_adda_id()
);

drop policy if exists parties_delete_authorized on public.parties;
create policy parties_delete_authorized
on public.parties
for delete
to authenticated
using (
  public.is_super_admin()
  or adda_id = public.current_user_adda_id()
);

revoke all on public.parties from anon;
grant select, insert, update, delete on public.parties to authenticated;

commit;
