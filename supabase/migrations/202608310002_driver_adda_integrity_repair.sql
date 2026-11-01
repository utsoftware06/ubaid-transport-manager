begin;

do $$
declare
  v_target_adda constant uuid:='44b73002-7582-4c75-aca8-24d853311674';
  v_sajjad constant uuid:='5fbd66fc-6a0d-4146-b952-1c272ae9f8f1';
  v_sajjad_old constant uuid:='fa248d2a-9b0d-4bcf-9f4a-580d202226f7';
  v_ubaid constant uuid:='71d1d0a6-e056-4769-83c3-0bf31a8a2947';
  v_ubaid_old constant uuid:='2e249521-cd54-4290-adf8-915b64d9850e';
  v_affected integer;
  v_sajjad_before jsonb;
  v_ubaid_before jsonb;
  v_sajjad_after jsonb;
  v_ubaid_after jsonb;
begin
  -- Sajjad: database evidence. Ubaid: explicit business-owner confirmation.
  if not exists(select 1 from public.addas a where a.id=v_target_adda and lower(btrim(a.name))='ubaid goods transport') then
    raise exception 'Confirmed target Adda ID/name is missing or changed';
  end if;
  if exists(select 1 from public.addas a where a.id in(v_sajjad_old,v_ubaid_old)) then
    raise exception 'An expected stale Adda UUID now resolves to a real Adda; repair assumptions changed';
  end if;

  select to_jsonb(d) into v_sajjad_before from public.drivers d where d.id=v_sajjad and d.adda_id=v_sajjad_old for update;
  if v_sajjad_before is null then raise exception 'Sajjad exact ID/old Adda guard failed'; end if;
  select to_jsonb(d) into v_ubaid_before from public.drivers d where d.id=v_ubaid and d.adda_id=v_ubaid_old for update;
  if v_ubaid_before is null then raise exception 'Ubaid exact ID/old Adda guard failed'; end if;
  if (select count(*) from public.drivers d left join public.addas a on a.id=d.adda_id where d.adda_id is null or a.id is null)<>2 then
    raise exception 'Invalid Driver/Adda scope changed; expected exactly two rows';
  end if;
  if (select count(*) from public.loadings l where l.driver_id=v_sajjad)<>6 then
    raise exception 'Sajjad Loading evidence count changed; expected six';
  end if;
  if exists(select 1 from public.loadings l left join public.vehicles v on v.id=l.vehicle_id where l.driver_id=v_sajjad and v.adda_id is distinct from v_target_adda) then
    raise exception 'Sajjad Vehicle/Adda evidence is incomplete or contradictory';
  end if;
  if exists(select 1 from public.loadings l left join public.bookings b on b.id=l.booking_id where l.driver_id=v_sajjad and l.booking_id is not null and b.adda_id is distinct from v_target_adda) then
    raise exception 'Sajjad Booking/Adda evidence is incomplete or contradictory';
  end if;
  if exists(
    select 1 from (
      select v.adda_id from public.loadings l join public.vehicles v on v.id=l.vehicle_id where l.driver_id=v_ubaid
      union all select b.adda_id from public.loadings l join public.bookings b on b.id=l.booking_id where l.driver_id=v_ubaid
      union all select t.adda_id from public.trips t where t.driver_id=v_ubaid and t.adda_id is not null
      union all select v.adda_id from public.trips t join public.vehicles v on v.id=t.vehicle_id where t.driver_id=v_ubaid
      union all select b.adda_id from public.trips t join public.bookings b on b.id=t.booking_id where t.driver_id=v_ubaid
      union all select audit.adda_id from public.audit_logs audit join public.addas audit_adda on audit_adda.id=audit.adda_id
        where audit.table_name='drivers' and (audit.record_id=v_ubaid::text or audit.old_data->>'id'=v_ubaid::text or audit.new_data->>'id'=v_ubaid::text)
      union all select v.adda_id from public.cashbook_entries cb join public.vehicles v on v.id=cb.vehicle_id where cb.driver_id=v_ubaid
    ) evidence where evidence.adda_id is distinct from v_target_adda
  ) then
    raise exception 'Ubaid has new contradictory authoritative Adda evidence; owner-confirmed repair is no longer safe';
  end if;

  update public.drivers d set adda_id=v_target_adda
  where (d.id=v_sajjad and d.adda_id=v_sajjad_old)
     or (d.id=v_ubaid and d.adda_id=v_ubaid_old);
  get diagnostics v_affected=row_count;
  if v_affected<>2 then raise exception 'Guarded repair changed % rows; expected exactly 2',v_affected; end if;

  select to_jsonb(d) into v_sajjad_after from public.drivers d where d.id=v_sajjad and d.adda_id=v_target_adda;
  select to_jsonb(d) into v_ubaid_after from public.drivers d where d.id=v_ubaid and d.adda_id=v_target_adda;
  if v_sajjad_after is null or v_ubaid_after is null then raise exception 'Post-update target Adda verification failed'; end if;
  if (v_sajjad_before-'adda_id') is distinct from (v_sajjad_after-'adda_id')
     or (v_ubaid_before-'adda_id') is distinct from (v_ubaid_after-'adda_id') then
    raise exception 'A non-Adda Driver field changed; rolling back repair';
  end if;
  if exists(select 1 from public.drivers d left join public.addas a on a.id=d.adda_id where d.adda_id is null or a.id is null) then
    raise exception 'Invalid Driver/Adda rows remain or appeared during repair';
  end if;
end $$;

commit;
