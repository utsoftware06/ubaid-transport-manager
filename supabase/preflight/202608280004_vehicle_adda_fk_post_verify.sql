-- UT Software — Vehicle -> Adda FK post-deployment verification
-- STRICTLY READ ONLY. No DDL, DML, grants, RPC calls, or mutations.

with
column_numbers as (
  select
    (select attnum from pg_attribute where attrelid=to_regclass('public.vehicles') and attname='adda_id' and not attisdropped) vehicle_adda_attnum,
    (select attnum from pg_attribute where attrelid=to_regclass('public.addas') and attname='id' and not attisdropped) adda_id_attnum
),
matching_fk as (
  select constraint_row.*
  from pg_constraint constraint_row
  cross join column_numbers columns
  where constraint_row.contype='f'
    and constraint_row.conrelid=to_regclass('public.vehicles')
    and constraint_row.confrelid=to_regclass('public.addas')
    and constraint_row.conkey=array[columns.vehicle_adda_attnum]::smallint[]
    and constraint_row.confkey=array[columns.adda_id_attnum]::smallint[]
),
checks(check_name,status,details,blocking) as (
  values
  ('SEMANTIC_FK_EXISTS',case when (select count(*) from matching_fk)=1 then 'PASS' else 'FAIL' end,coalesce((select string_agg(conname||' ['||pg_get_constraintdef(oid)||']',', ') from matching_fk),'No semantic Vehicle -> Adda FK found.'),true),
  ('STABLE_CONSTRAINT_NAME',case when exists(select 1 from matching_fk where conname='vehicles_adda_id_fkey') then 'PASS' else 'FAIL' end,'Expected constraint name: vehicles_adda_id_fkey.',true),
  ('FK_VALIDATED',case when exists(select 1 from matching_fk where convalidated) then 'PASS' else 'FAIL' end,'The FK must be fully validated.',true),
  ('DELETE_UPDATE_ACTIONS',case when exists(select 1 from matching_fk where confdeltype='r' and confupdtype='a') then 'PASS' else 'FAIL' end,'Expected ON DELETE RESTRICT and ON UPDATE NO ACTION.',true),
  ('ZERO_NULL_ADDA_IDS',case when not exists(select 1 from public.vehicles where adda_id is null) then 'PASS' else 'FAIL' end,(select format('%s Vehicle row(s) have NULL adda_id.',count(*)) from public.vehicles where adda_id is null),true),
  ('ZERO_ORPHAN_VEHICLES',case when not exists(select 1 from public.vehicles vehicle left join public.addas adda on adda.id=vehicle.adda_id where adda.id is null) then 'PASS' else 'FAIL' end,(select format('%s orphan Vehicle row(s).',count(*)) from public.vehicles vehicle left join public.addas adda on adda.id=vehicle.adda_id where adda.id is null),true),
  ('VEHICLE_DATA_SNAPSHOT','INFO',(select format('row_count=%s; id_adda_fingerprint=%s. Compare with preflight snapshot; migration also aborted internally if either changed.',count(*),md5(coalesce(string_agg(id::text||':'||adda_id::text,'|' order by id::text),''))) from public.vehicles),false),
  ('NO_BUSINESS_DATA_REWRITE','INFO','Migration contains only ADD CONSTRAINT, VALIDATE CONSTRAINT and read-only safety snapshots; no Vehicle/Adda DML.',false)
), combined as (
  select 'OVERALL_VEHICLE_ADDA_FK_POST_VERIFY'::text check_name,
    case when count(*) filter(where blocking and status='FAIL')=0 then 'PASS' else 'FAIL' end status,
    format('%s blocking check(s) failed; %s passed; %s informational',count(*) filter(where blocking and status='FAIL'),count(*) filter(where status='PASS'),count(*) filter(where status='INFO')) details
  from checks
  union all select check_name,status,details from checks
)
select check_name,status,details from combined
order by case when check_name='OVERALL_VEHICLE_ADDA_FK_POST_VERIFY' then 0 else 1 end,check_name;
