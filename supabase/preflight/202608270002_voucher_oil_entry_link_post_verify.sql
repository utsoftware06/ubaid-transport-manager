-- STRICTLY READ-ONLY post-migration verification for 202608270001.
with function_contract as (
  select p.oid,
    p.prosecdef,
    p.proconfig,
    pg_get_function_identity_arguments(p.oid) as identity_arguments,
    pg_get_functiondef(p.oid) as definition,
    regexp_replace(lower(pg_get_functiondef(p.oid)), '[[:space:]]+', '', 'g') as normalized_definition
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='sync_voucher_oil_entries'
), cashbook_contract as (
  select p.oid,pg_get_functiondef(p.oid) as definition
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='ut_sync_voucher_cashbook'
    and pg_get_function_identity_arguments(p.oid)='p_voucher_id text'
), blocking_checks as (
  select 'TABLE_EXISTS'::text check_name,
    case when exists(
      select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relname='voucher_oil_entries' and c.relkind='r'
    ) then 'PASS' else 'FAIL' end status,
    'public.voucher_oil_entries must exist as a base table'::text details

  union all
  select 'REQUIRED_COLUMN_TYPES',
    case when count(*)=0 then 'PASS' else 'FAIL' end,
    coalesce(string_agg(v.column_name||' expected '||v.data_type,', '),'id uuid; voucher_id bigint; oil_vehicle_entry_id uuid; created_at timestamptz')
  from (values
    ('id','uuid'),('voucher_id','bigint'),('oil_vehicle_entry_id','uuid'),('created_at','timestamp with time zone')
  ) v(column_name,data_type)
  where not exists(
    select 1 from information_schema.columns c
    where c.table_schema='public' and c.table_name='voucher_oil_entries'
      and c.column_name=v.column_name and c.data_type=v.data_type
  )

  union all
  select 'PRIMARY_KEY_ID',
    case when exists(
      select 1 from pg_constraint c
      where c.conrelid=to_regclass('public.voucher_oil_entries') and c.contype='p'
        and pg_get_constraintdef(c.oid)='PRIMARY KEY (id)'
    ) then 'PASS' else 'FAIL' end,
    'Primary key must protect voucher_oil_entries.id'

  union all
  select 'VOUCHER_FOREIGN_KEY_CASCADE',
    case when exists(
      select 1 from pg_constraint c
      where c.conrelid=to_regclass('public.voucher_oil_entries') and c.contype='f'
        and c.confrelid=to_regclass('public.expenses') and c.confdeltype='c'
        and pg_get_constraintdef(c.oid) ilike 'FOREIGN KEY (voucher_id) REFERENCES expenses(id)%ON DELETE CASCADE%'
    ) then 'PASS' else 'FAIL' end,
    'voucher_id must reference expenses(id) ON DELETE CASCADE so Voucher deletion removes only the link'

  union all
  select 'OIL_ENTRY_FOREIGN_KEY_RESTRICT',
    case when exists(
      select 1 from pg_constraint c
      where c.conrelid=to_regclass('public.voucher_oil_entries') and c.contype='f'
        and c.confrelid=to_regclass('public.oil_vehicle_entries') and c.confdeltype='r'
        and pg_get_constraintdef(c.oid) ilike 'FOREIGN KEY (oil_vehicle_entry_id) REFERENCES oil_vehicle_entries(id)%ON DELETE RESTRICT%'
    ) then 'PASS' else 'FAIL' end,
    'oil_vehicle_entry_id must reference oil_vehicle_entries(id) ON DELETE RESTRICT'

  union all
  select 'OIL_ENTRY_UNIQUENESS',
    case when exists(
      select 1 from pg_constraint c where c.conrelid=to_regclass('public.voucher_oil_entries') and c.contype='u'
        and pg_get_constraintdef(c.oid)='UNIQUE (oil_vehicle_entry_id)'
    ) then 'PASS' else 'FAIL' end,
    'One persisted Oil Vehicle Entry may attach to at most one Voucher'

  union all
  select 'VOUCHER_OIL_PAIR_UNIQUENESS',
    case when exists(
      select 1 from pg_constraint c where c.conrelid=to_regclass('public.voucher_oil_entries') and c.contype='u'
        and pg_get_constraintdef(c.oid)='UNIQUE (voucher_id, oil_vehicle_entry_id)'
    ) then 'PASS' else 'FAIL' end,
    'The voucher_id + oil_vehicle_entry_id pair must be unique'

  union all
  select 'VOUCHER_LOOKUP_INDEX',
    case when exists(
      select 1 from pg_index i
      where i.indrelid=to_regclass('public.voucher_oil_entries')
        and pg_get_indexdef(i.indexrelid) ilike '%(voucher_id)%'
    ) then 'PASS' else 'FAIL' end,
    'An index beginning with voucher_id must support Voucher link lookups'

  union all
  select 'RLS_ENABLED',
    case when exists(
      select 1 from pg_class c where c.oid=to_regclass('public.voucher_oil_entries') and c.relrowsecurity
    ) then 'PASS' else 'FAIL' end,
    'Row-level security must be enabled'

  union all
  select 'AUTHENTICATED_SELECT_POLICY',
    case when exists(
      select 1 from pg_policies p
      where p.schemaname='public' and p.tablename='voucher_oil_entries'
        and p.cmd='SELECT' and 'authenticated'=any(p.roles)
        and p.qual ilike '%current_user_adda_id%'
        and p.qual ilike '%oil_vehicle_entries%'
        and p.qual ilike '%booking_id%'
        and p.qual ilike '%vehicles%'
    ) then 'PASS' else 'FAIL' end,
    'Authenticated SELECT policy must retain Adda, Oil Entry, vehicle and legacy Booking fallback checks'

  union all
  select 'DIRECT_BROWSER_MUTATION_BLOCKED',
    case when not has_table_privilege('authenticated','public.voucher_oil_entries','INSERT')
      and not has_table_privilege('authenticated','public.voucher_oil_entries','UPDATE')
      and not has_table_privilege('authenticated','public.voucher_oil_entries','DELETE')
    then 'PASS' else 'FAIL' end,
    'Authenticated browser clients must not mutate linkage rows directly'

  union all
  select 'SYNC_RPC_EXACT_SIGNATURE',
    case when count(*)=1 and bool_and(identity_arguments='p_voucher_id bigint, p_oil_vehicle_entry_ids uuid[]') then 'PASS' else 'FAIL' end,
    count(*)||' matching public.sync_voucher_oil_entries function(s); expected exactly one bigint, uuid[] identity'
  from function_contract

  union all
  select 'SYNC_RPC_SECURITY',
    case when count(*)=1 and bool_and(prosecdef)
      and bool_and(exists(
        select 1 from unnest(coalesce(proconfig,array[]::text[])) setting
        where setting in ('search_path=""','search_path=')
      ))
    then 'PASS' else 'FAIL' end,
    'RPC must be SECURITY DEFINER with an empty locked search_path'
  from function_contract

  union all
  select 'SYNC_RPC_GRANTS',
    case when to_regprocedure('public.sync_voucher_oil_entries(bigint,uuid[])') is not null
      and has_function_privilege('authenticated','public.sync_voucher_oil_entries(bigint,uuid[])','EXECUTE')
      and not has_function_privilege('anon','public.sync_voucher_oil_entries(bigint,uuid[])','EXECUTE')
      and not exists(
        select 1
        from pg_proc p
        cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
        where p.oid=to_regprocedure('public.sync_voucher_oil_entries(bigint,uuid[])')
          and acl.grantee=0 and acl.privilege_type='EXECUTE'
      )
    then 'PASS' else 'FAIL' end,
    'Only authenticated must receive RPC execution access; anon and PUBLIC must be blocked'

  union all
  select 'SYNC_RPC_VALIDATION_CONTRACT',
    case when count(*)=1 and bool_and(
      normalized_definition like '%auth.uid()isnull%'
      and normalized_definition like '%public.current_user_role()notin(''super_admin'',''adda_admin'',''operator'')%'
      and normalized_definition like '%joinpublic.loadingslonl.id=e.loading_id%'
      and normalized_definition like '%leftjoinpublic.bookingsbonb.id=l.booking_id%'
      and normalized_definition like '%joinpublic.vehiclesvehicleonvehicle.id=l.vehicle_id%'
      and normalized_definition like '%joinpublic.addascontext_addaoncontext_adda.id=(casewhenl.booking_idisnullthenvehicle.adda_idelseb.adda_idend)%'
      and normalized_definition like '%wheree.id=p_voucher_id%'
      and normalized_definition like '%ifnotfoundthenraiseexception%'
      and normalized_definition like '%notpublic.is_super_admin()andvoucher_record.adda_idisdistinctfrompublic.current_user_adda_id()%'
      and normalized_definition like '%o.id=any(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[]))%'
      and normalized_definition like '%o.adda_id=voucher_record.adda_id%'
      and normalized_definition like '%o.vehicle_id=voucher_record.vehicle_id%'
      and normalized_definition like '%coalesce(o.total_amount,0)>0%'
      and normalized_definition like '%v.oil_vehicle_entry_id=o.idandv.voucher_id<>p_voucher_id%'
      and normalized_definition like '%requested_count<>coalesce(array_length(p_oil_vehicle_entry_ids,1),0)%'
      and normalized_definition like '%valid_count<>requested_count%'
      and strpos(normalized_definition,'ifrequested_count<>')>0
      and strpos(normalized_definition,'deletefrompublic.voucher_oil_entries')>strpos(normalized_definition,'ifrequested_count<>')
      and normalized_definition like '%insertintopublic.voucher_oil_entries(voucher_id,oil_vehicle_entry_id)%'
    ) then 'PASS' else 'FAIL' end,
    'Normalized RPC body must validate all auth, role, Voucher/Loading, Booking-or-legacy Vehicle Adda, Oil Entry, positive total, exclusivity and complete UUID-set conditions before persistence'
  from function_contract

  union all
  select 'OIL_LINK_CASHBOOK_TRIGGER',
    case when exists(
      select 1 from pg_trigger t
      join pg_proc p on p.oid=t.tgfoid
      join pg_namespace n on n.oid=p.pronamespace
      where t.tgrelid=to_regclass('public.voucher_oil_entries') and not t.tgisinternal
        and t.tgname='voucher_oil_entries_sync_cashbook'
        and n.nspname='public' and p.proname='ut_sync_voucher_oil_link_cashbook'
        and t.tgenabled<>'D'
        and pg_get_triggerdef(t.oid) ilike '%AFTER INSERT OR DELETE%'
    ) then 'PASS' else 'FAIL' end,
    'Oil link INSERT/DELETE trigger must resynchronize the existing Voucher Cashbook reference'

  union all
  select 'OIL_LINK_TRIGGER_FUNCTION',
    case when to_regprocedure('public.ut_sync_voucher_oil_link_cashbook()') is not null
      and pg_get_functiondef(to_regprocedure('public.ut_sync_voucher_oil_link_cashbook()')) ilike '%ut_sync_voucher_cashbook%'
    then 'PASS' else 'FAIL' end,
    'Oil link trigger function must call the existing Voucher Cashbook synchronizer only'

  union all
  select 'LINKED_OIL_CASHBOOK_EXCLUSION',
    case when count(*)=1 and bool_and(
      definition ilike '%Oil / Lubricants%'
      and definition ilike '%voucher_oil_entries%'
      and definition ilike '%not (%'
    ) then 'PASS' else 'FAIL' end,
    'Linked Oil reference Voucher items must be excluded from Voucher Cash Out totals'
  from cashbook_contract

  union all
  select 'WORKSHOP_CASHBOOK_EXCLUSION_PRESERVED',
    case when count(*)=1 and bool_and(
      definition ilike '%Workshop%'
      and definition ilike '%voucher_workshop_entries%'
    ) then 'PASS' else 'FAIL' end,
    'Existing linked Workshop reference exclusion must remain present'
  from cashbook_contract

  union all
  select 'NO_ORPHAN_LINKS',
    case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' linkage row(s) reference a missing Voucher or Oil Vehicle Entry'
  from public.voucher_oil_entries l
  left join public.expenses e on e.id=l.voucher_id
  left join public.oil_vehicle_entries o on o.id=l.oil_vehicle_entry_id
  where e.id is null or o.id is null

  union all
  select 'NO_DUPLICATE_OIL_ENTRY_LINKS',
    case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' Oil Vehicle Entry ID(s) are linked more than once'
  from (
    select oil_vehicle_entry_id from public.voucher_oil_entries
    group by oil_vehicle_entry_id having count(*)>1
  ) duplicate_links

  union all
  select 'LINKED_CONTEXT_INTEGRITY',
    case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' deployed link(s) violate Voucher vehicle/Adda context or positive persisted Oil total'
  from public.voucher_oil_entries link
  join public.expenses e on e.id=link.voucher_id
  left join public.loadings l on l.id=e.loading_id
  left join public.bookings b on b.id=l.booking_id
  left join public.vehicles vehicle on vehicle.id=l.vehicle_id
  left join public.addas context_adda on context_adda.id=(case when l.booking_id is null then vehicle.adda_id else b.adda_id end)
  left join public.oil_vehicle_entries o on o.id=link.oil_vehicle_entry_id
  where l.id is null or vehicle.id is null or context_adda.id is null or o.id is null
    or (l.booking_id is not null and b.id is null)
    or o.vehicle_id is distinct from l.vehicle_id
    or o.adda_id is distinct from context_adda.id
    or coalesce(o.total_amount,0)<=0

  union all
  select 'NO_LINK_SPECIFIC_CASHBOOK_ROWS',
    case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' unexpected Oil-link-specific Cashbook row(s) exist'
  from public.cashbook_entries
  where reference_type in ('voucher_oil_entry','voucher_oil_entries','oil_voucher_link')
), informational_checks as (
  select 'INFO_TOTAL_VOUCHERS'::text check_name,'INFO'::text status,count(*)||' total Voucher row(s)'::text details from public.expenses
  union all select 'INFO_TOTAL_OIL_VEHICLE_ENTRIES','INFO',count(*)||' total authoritative Oil Vehicle Entry row(s)' from public.oil_vehicle_entries
  union all select 'INFO_TOTAL_VOUCHER_OIL_LINKS','INFO',count(*)||' total Voucher–Oil reference link row(s)' from public.voucher_oil_entries
  union all select 'INFO_TOTAL_CASHBOOK_ROWS','INFO',count(*)||' total Cashbook row(s)' from public.cashbook_entries
  union all select 'INFO_SOURCE_DATA_PRESERVATION','INFO',
    'The migration contains no historical backfill, Oil payment creation, or Oil/Workshop/Voucher source-row mutation; absolute before/after row equality requires a pre-deployment snapshot'
), combined_checks as (
  select check_name,status,details from blocking_checks
  union all
  select check_name,status,details from informational_checks
), overall as (
  select 'OVERALL_VOUCHER_OIL_POST_MIGRATION_VERIFY'::text check_name,
    case when count(*) filter(where status='FAIL')=0 then 'PASS' else 'FAIL' end status,
    count(*) filter(where status='FAIL')||' blocking check(s) failed; '
      ||count(*) filter(where status='PASS')||' passed; '
      ||count(*) filter(where status='INFO')||' informational' details
  from combined_checks
)
select check_name,status,details
from (
  select check_name,status,details from overall
  union all
  select check_name,status,details from combined_checks
) verification_results
order by case when check_name='OVERALL_VOUCHER_OIL_POST_MIGRATION_VERIFY' then 0 else 1 end,check_name;
