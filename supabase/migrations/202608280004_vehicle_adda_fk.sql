begin;

do $$
declare
  v_vehicle_count bigint;
  v_vehicle_fingerprint text;
begin
  if to_regclass('public.vehicles') is null or to_regclass('public.addas') is null then
    raise exception 'VEHICLE_ADDA_FK_PREFLIGHT: public.vehicles and public.addas are required';
  end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='vehicles' and column_name='adda_id' and data_type='uuid' and is_nullable='NO')
     or not exists(select 1 from information_schema.columns where table_schema='public' and table_name='addas' and column_name='id' and data_type='uuid' and is_nullable='NO') then
    raise exception 'VEHICLE_ADDA_FK_PREFLIGHT: vehicles.adda_id and addas.id must be uuid NOT NULL';
  end if;
  if exists(select 1 from public.vehicles where adda_id is null) then
    raise exception 'VEHICLE_ADDA_FK_PREFLIGHT: vehicles.adda_id contains NULL values';
  end if;
  if exists(select 1 from public.vehicles vehicle left join public.addas adda on adda.id=vehicle.adda_id where adda.id is null) then
    raise exception 'VEHICLE_ADDA_FK_PREFLIGHT: orphan Vehicle Adda references exist';
  end if;
  if exists (
    select 1 from pg_constraint constraint_row
    where constraint_row.contype='f'
      and constraint_row.conrelid='public.vehicles'::regclass
      and constraint_row.confrelid='public.addas'::regclass
      and constraint_row.conkey=array[(select attnum from pg_attribute where attrelid='public.vehicles'::regclass and attname='adda_id' and not attisdropped)]::smallint[]
      and constraint_row.confkey=array[(select attnum from pg_attribute where attrelid='public.addas'::regclass and attname='id' and not attisdropped)]::smallint[]
  ) then raise exception 'VEHICLE_ADDA_FK_PREFLIGHT: equivalent semantic FK already exists'; end if;
  if exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.contype='f'
      and constraint_row.conrelid='public.vehicles'::regclass
      and (select attnum from pg_attribute where attrelid='public.vehicles'::regclass and attname='adda_id' and not attisdropped)=any(constraint_row.conkey)
      and not (
        constraint_row.confrelid='public.addas'::regclass
        and constraint_row.conkey=array[(select attnum from pg_attribute where attrelid='public.vehicles'::regclass and attname='adda_id' and not attisdropped)]::smallint[]
        and constraint_row.confkey=array[(select attnum from pg_attribute where attrelid='public.addas'::regclass and attname='id' and not attisdropped)]::smallint[]
      )
  ) then raise exception 'VEHICLE_ADDA_FK_PREFLIGHT: a conflicting FK already includes vehicles.adda_id'; end if;
  if exists(select 1 from pg_constraint where conrelid='public.vehicles'::regclass and conname='vehicles_adda_id_fkey') then
    raise exception 'VEHICLE_ADDA_FK_PREFLIGHT: constraint name vehicles_adda_id_fkey is already occupied';
  end if;

  select count(*),md5(coalesce(string_agg(id::text||':'||adda_id::text,'|' order by id::text),''))
    into v_vehicle_count,v_vehicle_fingerprint from public.vehicles;
  perform set_config('ut.vehicle_adda_fk.row_count',v_vehicle_count::text,true);
  perform set_config('ut.vehicle_adda_fk.fingerprint',v_vehicle_fingerprint,true);
end $$;

alter table public.vehicles
  add constraint vehicles_adda_id_fkey
  foreign key (adda_id)
  references public.addas(id)
  on update no action
  on delete restrict
  not valid;

alter table public.vehicles validate constraint vehicles_adda_id_fkey;

do $$
declare
  v_vehicle_count bigint;
  v_vehicle_fingerprint text;
begin
  select count(*),md5(coalesce(string_agg(id::text||':'||adda_id::text,'|' order by id::text),''))
    into v_vehicle_count,v_vehicle_fingerprint from public.vehicles;
  if v_vehicle_count::text is distinct from current_setting('ut.vehicle_adda_fk.row_count',true)
     or v_vehicle_fingerprint is distinct from current_setting('ut.vehicle_adda_fk.fingerprint',true) then
    raise exception 'VEHICLE_ADDA_FK_SAFETY: Vehicle rows changed while adding the FK; transaction aborted';
  end if;
end $$;

commit;
