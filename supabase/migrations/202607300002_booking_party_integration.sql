begin;

do $$
begin
  if to_regclass('public.bookings') is null then
    raise exception 'public.bookings must exist before applying Party integration';
  end if;

  if to_regclass('public.parties') is null then
    raise exception 'public.parties must exist before applying Party integration';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'bookings'
      and column_name = 'adda_id'
  ) then
    raise exception 'public.bookings.adda_id is required for tenant-safe Party integration';
  end if;
end;
$$;

alter table public.bookings
  add column if not exists party_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.bookings'::regclass
      and conname = 'bookings_party_id_fkey'
  ) then
    alter table public.bookings
      add constraint bookings_party_id_fkey
      foreign key (party_id)
      references public.parties(id)
      on delete restrict;
  end if;
end;
$$;

create index if not exists bookings_party_id_idx
  on public.bookings (party_id);

create or replace function public.validate_booking_party_adda()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  party_adda_id uuid;
begin
  if new.party_id is null then
    return new;
  end if;

  select party.adda_id
  into party_adda_id
  from public.parties as party
  where party.id = new.party_id;

  if party_adda_id is null or party_adda_id is distinct from new.adda_id then
    raise exception using
      errcode = '23514',
      message = 'Selected Party must belong to the Booking Adda';
  end if;

  return new;
end;
$$;

drop trigger if exists bookings_validate_party_adda on public.bookings;

create trigger bookings_validate_party_adda
before insert or update of party_id, adda_id on public.bookings
for each row
execute function public.validate_booking_party_adda();

commit;
