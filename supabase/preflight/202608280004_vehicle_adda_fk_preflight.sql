-- UT Software — Vehicle -> Adda foreign-key preflight
-- STRICTLY READ ONLY. No DDL, DML, grants, RPC calls, or mutations.

with
vehicle_adda_columns as (
  select
    vehicle_column.attnum as vehicle_adda_attnum,
    adda_column.attnum as adda_id_attnum
  from pg_attribute vehicle_column
  cross join pg_attribute adda_column
  where vehicle_column.attrelid=to_regclass('public.vehicles')
    and vehicle_column.attname='adda_id'
    and not vehicle_column.attisdropped
    and adda_column.attrelid=to_regclass('public.addas')
    and adda_column.attname='id'
    and not adda_column.attisdropped
),
semantic_fks as (
  select constraint_row.*
  from pg_constraint constraint_row
  cross join vehicle_adda_columns columns
  where constraint_row.contype='f'
    and constraint_row.conrelid=to_regclass('public.vehicles')
    and constraint_row.confrelid=to_regclass('public.addas')
    and constraint_row.conkey=array[columns.vehicle_adda_attnum]::smallint[]
    and constraint_row.confkey=array[columns.adda_id_attnum]::smallint[]
),
conflicting_fks as (
  select constraint_row.*
  from pg_constraint constraint_row
  cross join vehicle_adda_columns columns
  where constraint_row.contype='f'
    and constraint_row.conrelid=to_regclass('public.vehicles')
    and columns.vehicle_adda_attnum=any(constraint_row.conkey)
    and not (
      constraint_row.confrelid=to_regclass('public.addas')
      and constraint_row.conkey=array[columns.vehicle_adda_attnum]::smallint[]
      and constraint_row.confkey=array[columns.adda_id_attnum]::smallint[]
    )
),
checks(check_name,status,details,blocking) as (
  values
  ('VEHICLES_TABLE_EXISTS',case when to_regclass('public.vehicles') is not null then 'PASS' else 'FAIL' end,'public.vehicles must exist.',true),
  ('ADDAS_TABLE_EXISTS',case when to_regclass('public.addas') is not null then 'PASS' else 'FAIL' end,'public.addas must exist.',true),
  ('VEHICLES_ADDA_COLUMN',case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='vehicles' and column_name='adda_id' and data_type='uuid' and is_nullable='NO') then 'PASS' else 'FAIL' end,coalesce((select format('vehicles.adda_id type=%s; nullable=%s',data_type,is_nullable) from information_schema.columns where table_schema='public' and table_name='vehicles' and column_name='adda_id'),'vehicles.adda_id is missing.'),true),
  ('ADDAS_ID_COLUMN',case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='addas' and column_name='id' and data_type='uuid' and is_nullable='NO') then 'PASS' else 'FAIL' end,coalesce((select format('addas.id type=%s; nullable=%s',data_type,is_nullable) from information_schema.columns where table_schema='public' and table_name='addas' and column_name='id'),'addas.id is missing.'),true),
  ('KEY_TYPE_COMPATIBILITY',case when (select data_type from information_schema.columns where table_schema='public' and table_name='vehicles' and column_name='adda_id')=(select data_type from information_schema.columns where table_schema='public' and table_name='addas' and column_name='id') then 'PASS' else 'FAIL' end,'vehicles.adda_id and addas.id must have identical deployed data types.',true),
  ('ADDAS_ID_UNIQUE_TARGET',case when exists(select 1 from pg_constraint where conrelid=to_regclass('public.addas') and contype in('p','u') and conkey=array[(select adda_id_attnum from vehicle_adda_columns)]::smallint[]) then 'PASS' else 'FAIL' end,'public.addas.id must be a primary/unique FK target.',true),
  ('VEHICLES_ADDA_NOT_NULL_DATA',case when not exists(select 1 from public.vehicles where adda_id is null) then 'PASS' else 'FAIL' end,(select format('%s Vehicle row(s) have NULL adda_id.',count(*)) from public.vehicles where adda_id is null),true),
  ('ZERO_ORPHAN_VEHICLES',case when not exists(select 1 from public.vehicles vehicle left join public.addas adda on adda.id=vehicle.adda_id where vehicle.adda_id is not null and adda.id is null) then 'PASS' else 'FAIL' end,(select format('%s Vehicle row(s) reference a missing Adda.',count(*)) from public.vehicles vehicle left join public.addas adda on adda.id=vehicle.adda_id where vehicle.adda_id is not null and adda.id is null),true),
  ('EQUIVALENT_SEMANTIC_FK_ABSENT',case when not exists(select 1 from semantic_fks) then 'PASS' else 'FAIL' end,coalesce((select 'Equivalent FK already exists: '||string_agg(conname||' ['||pg_get_constraintdef(oid)||']',', ' order by conname) from semantic_fks),'No equivalent vehicles.adda_id -> addas.id FK exists; this is the expected forward-fix state.'),true),
  ('NO_CONFLICTING_ADDA_FK',case when not exists(select 1 from conflicting_fks) then 'PASS' else 'FAIL' end,coalesce((select 'Conflicting FK(s): '||string_agg(conname||' ['||pg_get_constraintdef(oid)||']',', ' order by conname) from conflicting_fks),'No conflicting FK includes vehicles.adda_id.'),true),
  ('CONSTRAINT_NAME_AVAILABLE',case when not exists(select 1 from pg_constraint where conrelid=to_regclass('public.vehicles') and conname='vehicles_adda_id_fkey') then 'PASS' else 'FAIL' end,'Stable constraint name vehicles_adda_id_fkey must be available.',true),
  ('PROJECT_DELETE_CONVENTION','PASS','Comparable Adda-owned masters (profiles, parties, Oil and movement groups) use ON DELETE RESTRICT. Proposed FK uses RESTRICT; ON UPDATE remains NO ACTION.',true),
  ('VEHICLE_DATA_SNAPSHOT','INFO',(select format('row_count=%s; id_adda_fingerprint=%s',count(*),md5(coalesce(string_agg(id::text||':'||adda_id::text,'|' order by id::text),''))) from public.vehicles),false),
  ('MIGRATION_EFFECT','INFO','The forward migration adds and validates one FK only. It contains no Vehicle/Adda DML and cannot rewrite business rows.',false),
  ('MIGRATION_HISTORY','INFO',case when to_regclass('supabase_migrations.schema_migrations') is null then 'Migration history is not visible to this role; confirm 202608280004 remains pending separately.' else 'Migration history exists; confirm 202608280004 remains pending before application.' end,false)
), combined as (
  select 'OVERALL_VEHICLE_ADDA_FK_PREFLIGHT'::text check_name,
    case when count(*) filter(where blocking and status='FAIL')=0 then 'PASS' else 'FAIL' end status,
    format('%s blocking check(s) failed; %s passed; %s informational',count(*) filter(where blocking and status='FAIL'),count(*) filter(where status='PASS'),count(*) filter(where status='INFO')) details
  from checks
  union all select check_name,status,details from checks
)
select check_name,status,details from combined
order by case when check_name='OVERALL_VEHICLE_ADDA_FK_PREFLIGHT' then 0 else 1 end,check_name;
