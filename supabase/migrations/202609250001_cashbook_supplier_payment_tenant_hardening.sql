-- CB-2D6 supplier-payment Cashbook tenant hardening.
-- No existing business rows are changed by this migration. Runtime DML below is
-- inside function bodies only and executes later through approved source flows.
-- Petrol payment 3 / Cashbook row 41 has no surviving authoritative Booking
-- chain. It is a reviewed historical exception, remains adda_id NULL, and is
-- never inferred, backfilled, or rewritten here.
begin;
do $$
begin
  if to_regclass('public.cashbook_entries') is null or to_regclass('public.addas') is null or to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)') is null then raise exception 'CB2D6_PREFLIGHT: Stage A/helper foundation missing'; end if;
  if not exists(select 1 from pg_catalog.pg_attribute a where a.attrelid='public.cashbook_entries'::regclass and a.attname='adda_id' and a.atttypid='uuid'::regtype and not a.attnotnull and not a.atthasdef) then raise exception 'CB2D6_PREFLIGHT: Cashbook adda_id structure drift'; end if;
  if not exists(select 1 from pg_catalog.pg_constraint c where c.conrelid='public.cashbook_entries'::regclass and c.contype='f' and c.convalidated and c.confdeltype='r' and c.confrelid='public.addas'::regclass and c.conkey=ARRAY[(select attnum from pg_catalog.pg_attribute where attrelid='public.cashbook_entries'::regclass and attname='adda_id')]::smallint[] and c.confkey=ARRAY[(select attnum from pg_catalog.pg_attribute where attrelid='public.addas'::regclass and attname='id')]::smallint[]) then raise exception 'CB2D6_PREFLIGHT: validated Adda RESTRICT FK missing'; end if;
  if not exists(select 1 from pg_catalog.pg_index i where i.indrelid='public.cashbook_entries'::regclass and i.indisvalid and i.indisready and i.indpred is not null and pg_catalog.pg_get_indexdef(i.indexrelid) ilike '%(adda_id, entry_date)%' and pg_catalog.pg_get_expr(i.indpred,i.indrelid) ilike '%adda_id IS NOT NULL%') then raise exception 'CB2D6_PREFLIGHT: Stage A index missing'; end if;
  if not exists(select 1 from pg_catalog.pg_index i join pg_catalog.pg_class idx on idx.oid=i.indexrelid where idx.relname='cashbook_entries_petrol_pump_payment_reference_uidx' and i.indisunique and i.indisvalid and i.indisready and pg_catalog.pg_get_indexdef(i.indexrelid) ilike '%(reference_type, reference_id)%' and pg_catalog.pg_get_expr(i.indpred,i.indrelid) ilike '%reference_type%petrol_pump_payment%' and pg_catalog.pg_get_expr(i.indpred,i.indrelid) ilike '%reference_id IS NOT NULL%') or not exists(select 1 from pg_catalog.pg_index i join pg_catalog.pg_class idx on idx.oid=i.indexrelid where idx.relname='cashbook_entries_oil_supplier_reference_uidx' and i.indisunique and i.indisvalid and i.indisready and pg_catalog.pg_get_indexdef(i.indexrelid) ilike '%(reference_type, reference_id)%' and pg_catalog.pg_get_expr(i.indpred,i.indrelid) ilike '%reference_type%oil_supplier_payment%' and pg_catalog.pg_get_expr(i.indpred,i.indrelid) ilike '%reference_id IS NOT NULL%') or (select count(*) from pg_catalog.pg_index i join pg_catalog.pg_class idx on idx.oid=i.indexrelid where idx.relname in ('cashbook_entries_tyre_shop_payment_uidx','cashbook_entries_tyre_shop_payment_reference_uidx') and i.indisunique and i.indisvalid and i.indisready and pg_catalog.pg_get_indexdef(i.indexrelid) ilike '%(reference_type, reference_id)%' and pg_catalog.pg_get_expr(i.indpred,i.indrelid) ilike '%reference_type%tyre_shop_payment%' and pg_catalog.pg_get_expr(i.indpred,i.indrelid) ilike '%reference_id IS NOT NULL%')<>2 then raise exception 'CB2D6_PREFLIGHT: source identity unique-index contract drift'; end if;
  if (select count(distinct idx.relname) from pg_catalog.pg_index i join pg_catalog.pg_class idx on idx.oid=i.indexrelid where i.indrelid='public.cashbook_entries'::regclass and idx.relname in ('cashbook_entries_petrol_pump_payment_reference_uidx','cashbook_entries_oil_supplier_reference_uidx','cashbook_entries_tyre_shop_payment_uidx','cashbook_entries_tyre_shop_payment_reference_uidx') and i.indisunique and i.indisvalid and i.indisready and pg_catalog.pg_get_indexdef(i.indexrelid) ilike '%(reference_type, reference_id)%' and pg_catalog.pg_get_expr(i.indpred,i.indrelid) ilike '%reference_id IS NOT NULL%' and ((idx.relname='cashbook_entries_petrol_pump_payment_reference_uidx' and pg_catalog.pg_get_expr(i.indpred,i.indrelid) ilike '%petrol_pump_payment%') or (idx.relname='cashbook_entries_oil_supplier_reference_uidx' and pg_catalog.pg_get_expr(i.indpred,i.indrelid) ilike '%oil_supplier_payment%') or (idx.relname in ('cashbook_entries_tyre_shop_payment_uidx','cashbook_entries_tyre_shop_payment_reference_uidx') and pg_catalog.pg_get_expr(i.indpred,i.indrelid) ilike '%tyre_shop_payment%')))<>4 then raise exception 'CB2D6_PREFLIGHT: exact Cashbook source indexes are not attached to cashbook_entries'; end if;
  if (select count(*) from public.cashbook_entries)<>39 or (select count(*) from public.cashbook_entries where adda_id is not null)<>21 or (select count(*) from public.cashbook_entries where adda_id is null)<>18 then raise exception 'CB2D6_PREFLIGHT: 39/21/18 reviewed baseline drift'; end if;
  if to_regprocedure('public.ut_validate_petrol_pump_payment_tenant(uuid)') is null or to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)') is null or to_regprocedure('public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)') is null or to_regprocedure('public.delete_petrol_pump_payment(bigint)') is null or to_regprocedure('public.rebuild_oil_supplier_accounting(uuid)') is null or to_regprocedure('public.save_oil_supplier_payment(bigint,uuid,date,numeric,numeric,text,text,text)') is null or to_regprocedure('public.delete_oil_supplier_payment(bigint)') is null or to_regprocedure('public.rebuild_tyre_shop_accounting(uuid)') is null or to_regprocedure('public.save_tyre_shop_payment(bigint,uuid,date,numeric,numeric,text,text,text)') is null or to_regprocedure('public.delete_tyre_shop_payment(bigint)') is null then raise exception 'CB2D6_PREFLIGHT: required function signature missing'; end if;
  if (select count(*) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('ut_validate_petrol_pump_payment_tenant','rebuild_petrol_pump_accounting','save_petrol_pump_payment','delete_petrol_pump_payment','rebuild_oil_supplier_accounting','save_oil_supplier_payment','delete_oil_supplier_payment','rebuild_tyre_shop_accounting','save_tyre_shop_payment','delete_tyre_shop_payment'))<>10 then raise exception 'CB2D6_PREFLIGHT: unexpected overload/duplicate supplier routine'; end if;
  if exists(select 1 from pg_catalog.pg_proc p where p.oid in ('public.ut_validate_petrol_pump_payment_tenant(uuid)'::regprocedure,'public.rebuild_petrol_pump_accounting(uuid)'::regprocedure,'public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'::regprocedure,'public.delete_petrol_pump_payment(bigint)'::regprocedure,'public.rebuild_oil_supplier_accounting(uuid)'::regprocedure,'public.save_oil_supplier_payment(bigint,uuid,date,numeric,numeric,text,text,text)'::regprocedure,'public.delete_oil_supplier_payment(bigint)'::regprocedure,'public.rebuild_tyre_shop_accounting(uuid)'::regprocedure,'public.save_tyre_shop_payment(bigint,uuid,date,numeric,numeric,text,text,text)'::regprocedure,'public.delete_tyre_shop_payment(bigint)'::regprocedure) and (p.proowner<>(select oid from pg_catalog.pg_roles where rolname='postgres') or not p.prosecdef or p.provolatile<>'v' or regexp_replace(coalesce(p.proconfig::text,''),'[{}", ]','','g')<>'search_path=publicpg_temp')) then raise exception 'CB2D6_PREFLIGHT: owner/security/search_path/volatility drift'; end if;
  if not exists(select 1 from pg_catalog.pg_proc p where p.oid='public.rebuild_petrol_pump_accounting(uuid)'::regprocedure and p.prosrc ilike '%petrol_pump_payment%' and p.prosrc ilike '%cashbook_entries%' and p.prosrc not ilike '%ut_cashbook_assert_source_adda_id%') or not exists(select 1 from pg_catalog.pg_proc p where p.oid='public.rebuild_oil_supplier_accounting(uuid)'::regprocedure and p.prosrc ilike '%oil_supplier_payment%' and p.prosrc ilike '%cashbook_entries%' and p.prosrc not ilike '%ut_cashbook_assert_source_adda_id%') or not exists(select 1 from pg_catalog.pg_proc p where p.oid='public.rebuild_tyre_shop_accounting(uuid)'::regprocedure and p.prosrc ilike '%tyre_shop_payment%' and p.prosrc ilike '%cashbook_entries%' and p.prosrc not ilike '%ut_cashbook_assert_source_adda_id%') or not exists(select 1 from pg_catalog.pg_proc p where p.oid='public.save_tyre_shop_payment(bigint,uuid,date,numeric,numeric,text,text,text)'::regprocedure and p.prosrc ilike '%delete from public.cashbook_entries%' and p.prosrc ilike '%rebuild_tyre_shop_accounting%') or not exists(select 1 from pg_catalog.pg_proc p where p.oid='public.delete_oil_supplier_payment(bigint)'::regprocedure and p.prosrc ilike '%delete from public.oil_supplier_payments%' and p.prosrc ilike '%rebuild_oil_supplier_accounting%' and strpos(lower(p.prosrc),'delete from public.oil_supplier_payments')<strpos(lower(p.prosrc),'rebuild_oil_supplier_accounting')) then raise exception 'CB2D6_PREFLIGHT: current writer starting definition drift'; end if;
  if not has_function_privilege('authenticated','public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'::regprocedure,'EXECUTE') or not has_function_privilege('authenticated','public.delete_petrol_pump_payment(bigint)'::regprocedure,'EXECUTE') or not has_function_privilege('authenticated','public.save_oil_supplier_payment(bigint,uuid,date,numeric,numeric,text,text,text)'::regprocedure,'EXECUTE') or not has_function_privilege('authenticated','public.delete_oil_supplier_payment(bigint)'::regprocedure,'EXECUTE') or not has_function_privilege('authenticated','public.save_tyre_shop_payment(bigint,uuid,date,numeric,numeric,text,text,text)'::regprocedure,'EXECUTE') or not has_function_privilege('authenticated','public.delete_tyre_shop_payment(bigint)'::regprocedure,'EXECUTE') then raise exception 'CB2D6_PREFLIGHT: approved authenticated save/delete RPC EXECUTE contract missing'; end if;
  if not exists(select 1 from pg_catalog.pg_proc p where p.oid='public.ut_cashbook_assert_source_adda_id(uuid,uuid)'::regprocedure and p.prorettype='uuid'::regtype and not p.prosecdef and p.provolatile='i' and p.proconfig @> ARRAY['search_path=""']::text[] and p.prosrc ilike '%p_authoritative_adda_id is null%' and p.prosrc ilike '%is distinct from%') or not has_function_privilege('postgres','public.ut_cashbook_assert_source_adda_id(uuid,uuid)'::regprocedure,'EXECUTE') or has_function_privilege('anon','public.ut_cashbook_assert_source_adda_id(uuid,uuid)'::regprocedure,'EXECUTE') or has_function_privilege('authenticated','public.ut_cashbook_assert_source_adda_id(uuid,uuid)'::regprocedure,'EXECUTE') then raise exception 'CB2D6_PREFLIGHT: helper contract/owner privilege boundary drift'; end if;
  if exists(select 1 from public.cashbook_entries where reference_type in ('petrol_pump_payment','oil_supplier_payment','tyre_shop_payment') group by reference_type,reference_id having count(*)>1) then raise exception 'CB2D6_PREFLIGHT: duplicate Cashbook source identities'; end if;
  if not exists(select 1 from public.petrol_pump_payments p join public.cashbook_entries c on c.id=41 and c.reference_type='petrol_pump_payment' and c.reference_id='3' where p.id=3 and p.payment_date=DATE '2026-08-19' and p.payment_now=41000 and p.payment_method='Cash' and c.amount=41000 and c.entry_type='Cash Out' and c.adda_id is null and not exists(select 1 from public.diesel_entries d where d.petrol_pump_id=p.petrol_pump_id) and not exists(select 1 from public.petrol_pump_payment_allocations a where a.payment_id=3)) then raise exception 'CB2D6_PREFLIGHT: Payment 3 / Cashbook 41 exception drift'; end if;
  if not exists(select 1 from public.petrol_pump_payments p join public.petrol_pumps pump on pump.id=p.petrol_pump_id where p.id=3) then raise exception 'CB2D6_PREFLIGHT: Payment 3 pump source missing'; end if;
  if (select count(*) from public.cashbook_entries where reference_type in ('petrol_pump_payment','oil_supplier_payment','tyre_shop_payment'))<>6 then raise exception 'CB2D6_PREFLIGHT: relevant Cashbook row count drift'; end if;
  if exists(select 1 from public.cashbook_entries c join public.petrol_pump_payments p on c.reference_type='petrol_pump_payment' and c.reference_id=p.id::text where p.id<>3 and ((select count(distinct b.adda_id) from public.diesel_entries d join public.loadings l on l.id=d.loading_id join public.bookings b on b.id=l.booking_id where d.petrol_pump_id=p.petrol_pump_id and b.adda_id is not null)<>1 or c.adda_id is null or c.adda_id is distinct from (select (array_agg(distinct b.adda_id) filter(where b.adda_id is not null))[1] from public.diesel_entries d join public.loadings l on l.id=d.loading_id join public.bookings b on b.id=l.booking_id where d.petrol_pump_id=p.petrol_pump_id and b.adda_id is not null) or c.amount is distinct from p.payment_now or c.entry_type is distinct from 'Cash Out')) then raise exception 'CB2D6_PREFLIGHT: non-exception Petrol tenant/accounting mismatch'; end if;
  if exists(select 1 from public.cashbook_entries c join public.oil_supplier_payments p on c.reference_type='oil_supplier_payment' and c.reference_id=p.id::text join public.oil_shops s on s.id=p.oil_shop_id where c.adda_id is distinct from s.adda_id or c.amount is distinct from p.payment_now or c.entry_type is distinct from 'Cash Out') then raise exception 'CB2D6_PREFLIGHT: Oil source/Cashbook tenant or accounting mismatch'; end if;
  if exists(select 1 from public.cashbook_entries c join public.tyre_shop_payments p on c.reference_type='tyre_shop_payment' and c.reference_id=p.id::text join public.tyre_shops s on s.id=p.tyre_shop_id where c.adda_id is distinct from s.adda_id or c.amount is distinct from p.payment_now or c.entry_type is distinct from 'Cash Out') then raise exception 'CB2D6_PREFLIGHT: Tyre source/Cashbook tenant or accounting mismatch'; end if;
  if exists(select 1 from public.cashbook_entries c where c.reference_type in ('petrol_pump_payment','oil_supplier_payment','tyre_shop_payment') and ((c.reference_type='petrol_pump_payment' and not exists(select 1 from public.petrol_pump_payments p where p.id::text=c.reference_id)) or (c.reference_type='oil_supplier_payment' and not exists(select 1 from public.oil_supplier_payments p where p.id::text=c.reference_id)) or (c.reference_type='tyre_shop_payment' and not exists(select 1 from public.tyre_shop_payments p where p.id::text=c.reference_id)))) then raise exception 'CB2D6_PREFLIGHT: orphan supplier Cashbook reference'; end if;
  if exists(select 1 from public.petrol_pump_payments p where p.id<>3 and p.payment_now>0 and not exists(select 1 from public.cashbook_entries c where c.reference_type='petrol_pump_payment' and c.reference_id=p.id::text)) or exists(select 1 from public.oil_supplier_payments p where p.payment_now>0 and not exists(select 1 from public.cashbook_entries c where c.reference_type='oil_supplier_payment' and c.reference_id=p.id::text)) or exists(select 1 from public.tyre_shop_payments p where p.payment_now>0 and not exists(select 1 from public.cashbook_entries c where c.reference_type='tyre_shop_payment' and c.reference_id=p.id::text)) then raise exception 'CB2D6_PREFLIGHT: expected supplier Cashbook row missing'; end if;
  if not exists(select 1 from pg_catalog.pg_index i join pg_catalog.pg_class idx on idx.oid=i.indexrelid where idx.relname='cashbook_entries_petrol_pump_payment_reference_uidx' and i.indisunique and i.indisvalid and i.indisready) or not exists(select 1 from pg_catalog.pg_index i join pg_catalog.pg_class idx on idx.oid=i.indexrelid where idx.relname='cashbook_entries_oil_supplier_reference_uidx' and i.indisunique and i.indisvalid and i.indisready) or (select count(*) from pg_catalog.pg_index i join pg_catalog.pg_class idx on idx.oid=i.indexrelid where idx.relname in ('cashbook_entries_tyre_shop_payment_uidx','cashbook_entries_tyre_shop_payment_reference_uidx') and i.indisunique and i.indisvalid and i.indisready)<>2 then raise exception 'CB2D6_PREFLIGHT: required exact-once Cashbook indexes missing/invalid'; end if;
  if not exists(select 1 from pg_catalog.pg_trigger t join pg_catalog.pg_class c on c.oid=t.tgrelid join pg_catalog.pg_proc p on p.oid=t.tgfoid where c.relname='petrol_pump_payments' and t.tgname='petrol_pump_payments_protect_accounting' and p.proname='ut_protect_petrol_pump_payment_mutations' and not t.tgisinternal and t.tgenabled<>'D') or not exists(select 1 from pg_catalog.pg_trigger t join pg_catalog.pg_class c on c.oid=t.tgrelid join pg_catalog.pg_proc p on p.oid=t.tgfoid where c.relname='oil_supplier_payments' and t.tgname='oil_supplier_payments_protect' and p.proname='ut_protect_oil_supplier_mutations' and not t.tgisinternal and t.tgenabled<>'D') or not exists(select 1 from pg_catalog.pg_trigger t join pg_catalog.pg_class c on c.oid=t.tgrelid join pg_catalog.pg_proc p on p.oid=t.tgfoid where c.relname='tyre_shop_payments' and t.tgname='tyre_shop_payments_protect' and p.proname='ut_protect_tyre_shop_accounting' and not t.tgisinternal and t.tgenabled<>'D') or not exists(select 1 from pg_catalog.pg_trigger t join pg_catalog.pg_class c on c.oid=t.tgrelid join pg_catalog.pg_proc p on p.oid=t.tgfoid where c.relname='cashbook_entries' and t.tgname='cashbook_entries_protect_automatic_sources' and p.proname='ut_protect_automatic_cashbook_entries' and not t.tgisinternal and t.tgenabled<>'D') or not exists(select 1 from pg_catalog.pg_trigger t join pg_catalog.pg_class c on c.oid=t.tgrelid join pg_catalog.pg_proc p on p.oid=t.tgfoid where c.relname='cashbook_entries' and t.tgname='cashbook_entries_protect_oil_supplier' and p.proname='ut_protect_oil_supplier_cashbook' and not t.tgisinternal and t.tgenabled<>'D') or not exists(select 1 from pg_catalog.pg_trigger t join pg_catalog.pg_class c on c.oid=t.tgrelid join pg_catalog.pg_proc p on p.oid=t.tgfoid where c.relname='cashbook_entries' and t.tgname='cashbook_entries_protect_tyre_shop' and p.proname='ut_protect_tyre_shop_cashbook' and not t.tgisinternal and t.tgenabled<>'D') then raise exception 'CB2D6_PREFLIGHT: existing source/Cashbook guard trigger drift'; end if;
  if not exists(select 1 from pg_catalog.pg_constraint c where c.conrelid='public.oil_shops'::regclass and c.contype='f' and c.confrelid='public.addas'::regclass and c.confdeltype='r' and c.convalidated) or not exists(select 1 from pg_catalog.pg_constraint c where c.conrelid='public.tyre_shops'::regclass and c.contype='f' and c.confrelid='public.addas'::regclass and c.confdeltype='r' and c.convalidated) or not exists(select 1 from pg_catalog.pg_constraint c where c.conrelid='public.oil_supplier_payments'::regclass and c.contype='f' and c.confrelid='public.oil_shops'::regclass and c.confdeltype='r' and c.convalidated) or not exists(select 1 from pg_catalog.pg_constraint c where c.conrelid='public.tyre_shop_payments'::regclass and c.contype='f' and c.confrelid='public.tyre_shops'::regclass and c.confdeltype='r' and c.convalidated) or not exists(select 1 from pg_catalog.pg_constraint c where c.conrelid='public.petrol_pump_payment_allocations'::regclass and c.contype='f' and c.confrelid='public.petrol_pump_payments'::regclass and c.confdeltype='c' and c.convalidated) or not exists(select 1 from pg_catalog.pg_constraint c where c.conrelid='public.petrol_pump_payment_allocations'::regclass and c.contype='f' and c.confrelid='public.diesel_entries'::regclass and c.confdeltype='r' and c.convalidated) then raise exception 'CB2D6_PREFLIGHT: source FK/delete-action contract drift'; end if;
  if not exists(select 1 from pg_catalog.pg_trigger t join pg_catalog.pg_class c on c.oid=t.tgrelid join pg_catalog.pg_proc p on p.oid=t.tgfoid join pg_catalog.pg_namespace n on n.oid=c.relnamespace and n.nspname='public' join pg_catalog.pg_namespace pn on pn.oid=p.pronamespace where c.relname='petrol_pump_payments' and t.tgname='diesel_settlement_after_pump_payment_change' and not t.tgisinternal and t.tgenabled<>'D' and pn.nspname='public' and p.proname='trigger_recalculate_petrol_pump_settlement') then raise exception 'CB2D6_PREFLIGHT: Petrol settlement trigger drift'; end if;
  if (select count(*) from pg_catalog.pg_trigger t join pg_catalog.pg_class c on c.oid=t.tgrelid join pg_catalog.pg_proc p on p.oid=t.tgfoid where c.relnamespace='public'::regnamespace and c.relname='tyre_vehicle_entries' and not t.tgisinternal and t.tgenabled<>'D' and ((t.tgname='tyre_vehicle_entries_protect' and p.proname='ut_tyre_protect_authoritative_rows') or (t.tgname='tyre_vehicle_entries_safe_delete_guard' and p.proname='ut_guard_tyre_vehicle_entry_delete') or (t.tgname='tyre_vehicle_entries_voucher_origin_guard' and p.proname='ut_protect_voucher_created_tyre_origin')))<>3 then raise exception 'CB2D6_PREFLIGHT: Tyre lifecycle trigger drift'; end if;
  if exists(
    select 1 from (values
      ('petrol_pump_payments','petrol_pump_payments_protect_accounting','ut_protect_petrol_pump_payment_mutations',31),
      ('petrol_pump_payments','diesel_settlement_after_pump_payment_change','trigger_recalculate_petrol_pump_settlement',NULL::integer),
      ('oil_purchases','oil_purchases_prepare_supplier_bill','ut_prepare_oil_supplier_source_mutation',31),
      ('oil_purchases','oil_purchases_supplier_bill','ut_sync_oil_supplier_source_bill',29),
      ('oil_vehicle_entries','oil_vehicle_entries_prepare_supplier_bill','ut_prepare_oil_supplier_source_mutation',31),
      ('oil_vehicle_entries','oil_vehicle_entries_supplier_bill','ut_sync_oil_supplier_source_bill',29),
      ('oil_supplier_bills','oil_supplier_bills_protect','ut_protect_oil_supplier_mutations',31),
      ('oil_supplier_payments','oil_supplier_payments_protect','ut_protect_oil_supplier_mutations',31),
      ('oil_supplier_payment_allocations','oil_supplier_allocations_protect','ut_protect_oil_supplier_mutations',31),
      ('tyre_vehicle_entries','tyre_vehicle_entries_shop_bill','ut_sync_tyre_shop_source_bill',29),
      ('tyre_vehicle_entries','tyre_vehicle_entries_protect','ut_tyre_protect_authoritative_rows',31),
      ('tyre_vehicle_entries','tyre_vehicle_entries_safe_delete_guard','ut_guard_tyre_vehicle_entry_delete',11),
      ('tyre_vehicle_entries','tyre_vehicle_entries_voucher_origin_guard','ut_protect_voucher_created_tyre_origin',19),
      ('tyre_shop_bills','tyre_shop_bills_protect','ut_protect_tyre_shop_accounting',31),
      ('tyre_shop_payments','tyre_shop_payments_protect','ut_protect_tyre_shop_accounting',31),
      ('tyre_shop_payment_allocations','tyre_shop_allocations_protect','ut_protect_tyre_shop_accounting',31),
      ('cashbook_entries','cashbook_entries_protect_automatic_sources','ut_protect_automatic_cashbook_entries',31),
      ('cashbook_entries','cashbook_entries_protect_oil_supplier','ut_protect_oil_supplier_cashbook',31),
      ('cashbook_entries','cashbook_entries_protect_tyre_shop','ut_protect_tyre_shop_cashbook',31),
      ('cashbook_entries','cashbook_entries_protect_driver_payment','ut_protect_driver_cashbook',31),
      ('cashbook_entries','cashbook_entries_protect_owner_gari_withdrawal','ut_protect_owner_gari_withdrawal_cashbook',31)
    ) expected(relation_name,trigger_name,function_name,expected_tgtype)
    left join pg_catalog.pg_class c on c.relname=expected.relation_name and c.relnamespace='public'::regnamespace
    left join pg_catalog.pg_trigger t on t.tgrelid=c.oid and t.tgname=expected.trigger_name and not t.tgisinternal
    left join pg_catalog.pg_proc p on p.oid=t.tgfoid
    left join pg_catalog.pg_namespace pn on pn.oid=p.pronamespace
    where t.oid is null or t.tgenabled<>'O' or pn.nspname<>'public' or p.proname<>expected.function_name
      or (expected.expected_tgtype is not null and t.tgtype<>expected.expected_tgtype)
  ) then raise exception 'CB2D6_PREFLIGHT: exact relevant trigger contract drift'; end if;
  if exists(
    select 1 from pg_catalog.pg_trigger t join pg_catalog.pg_class c on c.oid=t.tgrelid
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and not t.tgisinternal
      and c.relname in ('petrol_pump_payments','oil_purchases','oil_vehicle_entries','oil_supplier_bills','oil_supplier_payments','oil_supplier_payment_allocations','tyre_vehicle_entries','tyre_shop_bills','tyre_shop_payments','tyre_shop_payment_allocations','cashbook_entries')
      and not exists(select 1 from (values
        ('petrol_pump_payments','petrol_pump_payments_protect_accounting'),('petrol_pump_payments','diesel_settlement_after_pump_payment_change'),
        ('oil_purchases','oil_purchases_prepare_supplier_bill'),('oil_purchases','oil_purchases_supplier_bill'),
        ('oil_vehicle_entries','oil_vehicle_entries_prepare_supplier_bill'),('oil_vehicle_entries','oil_vehicle_entries_supplier_bill'),
        ('oil_supplier_bills','oil_supplier_bills_protect'),('oil_supplier_payments','oil_supplier_payments_protect'),('oil_supplier_payment_allocations','oil_supplier_allocations_protect'),
        ('tyre_vehicle_entries','tyre_vehicle_entries_shop_bill'),('tyre_vehicle_entries','tyre_vehicle_entries_protect'),('tyre_vehicle_entries','tyre_vehicle_entries_safe_delete_guard'),('tyre_vehicle_entries','tyre_vehicle_entries_voucher_origin_guard'),
        ('tyre_shop_bills','tyre_shop_bills_protect'),('tyre_shop_payments','tyre_shop_payments_protect'),('tyre_shop_payment_allocations','tyre_shop_allocations_protect'),
        ('cashbook_entries','cashbook_entries_protect_automatic_sources'),('cashbook_entries','cashbook_entries_protect_oil_supplier'),('cashbook_entries','cashbook_entries_protect_tyre_shop'),
        ('cashbook_entries','cashbook_entries_protect_driver_payment'),('cashbook_entries','cashbook_entries_protect_owner_gari_withdrawal')
      ) expected(relation_name,trigger_name) where expected.relation_name=c.relname and expected.trigger_name=t.tgname)
  ) then raise exception 'CB2D6_PREFLIGHT: unexpected relevant source trigger'; end if;
end $$;
create or replace function public.rebuild_petrol_pump_accounting(
  p_petrol_pump_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  opening_balance numeric := 0;
  opening_outstanding numeric := 0;
  available_advance numeric := 0;
  current_payable numeric := 0;
  payable_before numeric := 0;
  advance_before numeric := 0;
  settlement numeric := 0;
  settlement_remaining numeric := 0;
  applied_to_opening numeric := 0;
  applied_to_diesel numeric := 0;
  created_advance numeric := 0;
  payment_row record;
  diesel_row record;
  reversal_row record;
  source_adda uuid;
  source_adda_count integer;
  existing_cashbook_adda uuid;
begin
  if p_petrol_pump_id is null then
    raise exception using errcode = '22023', message = 'pump_required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_petrol_pump_id::text, 0));
  perform set_config('ut.petrol_pump_payment_sync', 'on', true);
  perform set_config('ut.cashbook_sync', 'on', true);

  select coalesce(pump.opening_balance, 0)
  into opening_balance
  from public.petrol_pumps pump
  where pump.id = p_petrol_pump_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'pump_not_found';
  end if;

  select count(distinct booking.adda_id),
         (array_agg(distinct booking.adda_id) filter (where booking.adda_id is not null))[1]
  into source_adda_count, source_adda
  from public.diesel_entries diesel
  join public.loadings loading on loading.id=diesel.loading_id
  join public.bookings booking on booking.id=loading.booking_id
  where diesel.petrol_pump_id=p_petrol_pump_id and booking.adda_id is not null;
  if source_adda_count<>1 or source_adda is null
     or not exists(select 1 from public.addas adda where adda.id=source_adda) then
    source_adda := null;
  end if;

  -- Reverse only amounts recorded by this module. Existing manual, voucher,
  -- or unrelated diesel paid amounts remain untouched.
  for reversal_row in
    select allocation.diesel_entry_id, sum(allocation.amount) as amount
    from public.petrol_pump_payment_allocations allocation
    join public.petrol_pump_payments payment
      on payment.id = allocation.payment_id
    where payment.petrol_pump_id = p_petrol_pump_id
    group by allocation.diesel_entry_id
    order by allocation.diesel_entry_id
  loop
    if not exists (
      select 1
      from public.diesel_entries diesel
      where diesel.id = reversal_row.diesel_entry_id
        and coalesce(diesel.paid_amount, 0) >= reversal_row.amount
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'Recorded petrol pump allocation exceeds the diesel paid amount; accounting rebuild stopped';
    end if;

    update public.diesel_entries diesel
    set paid_amount = coalesce(diesel.paid_amount, 0) - reversal_row.amount,
        remaining_amount = coalesce(diesel.remaining_amount, 0) + reversal_row.amount,
        payment_status = case
          when coalesce(diesel.paid_amount, 0) - reversal_row.amount <= 0
            then 'Unpaid'
          when coalesce(diesel.remaining_amount, 0) + reversal_row.amount > 0
            then 'Partial'
          else 'Paid'
        end
    where diesel.id = reversal_row.diesel_entry_id;
  end loop;

  delete from public.petrol_pump_payment_allocations allocation
  using public.petrol_pump_payments payment
  where payment.id = allocation.payment_id
    and payment.petrol_pump_id = p_petrol_pump_id;

  opening_outstanding := greatest(opening_balance, 0);
  available_advance := greatest(-opening_balance, 0);

  for payment_row in
    select payment.*
    from public.petrol_pump_payments payment
    where payment.petrol_pump_id = p_petrol_pump_id
    order by payment.payment_date, payment.created_at, payment.id
    for update
  loop
    if payment_row.advance_used < 0
      or payment_row.payment_now < 0
      or payment_row.advance_used::text in ('NaN', 'Infinity', '-Infinity')
      or payment_row.payment_now::text in ('NaN', 'Infinity', '-Infinity')
      or payment_row.advance_used + payment_row.payment_now <= 0
    then
      raise exception using errcode = '22023', message = 'invalid_amount';
    end if;

    payable_before := opening_outstanding + coalesce((
      select sum(greatest(coalesce(diesel.remaining_amount, 0), 0))
      from public.diesel_entries diesel
      where diesel.petrol_pump_id = p_petrol_pump_id
    ), 0);

    if payment_row.advance_used > available_advance
      or payment_row.advance_used > payable_before
    then
      raise exception using
        errcode = '22023',
        message = 'advance_exceeds_limit';
    end if;

    settlement := payment_row.advance_used + payment_row.payment_now;
    advance_before := available_advance;
    settlement_remaining := settlement;
    applied_to_opening := least(opening_outstanding, settlement_remaining);
    opening_outstanding := opening_outstanding - applied_to_opening;
    settlement_remaining := settlement_remaining - applied_to_opening;

    for diesel_row in
      select
        diesel.id,
        greatest(coalesce(diesel.remaining_amount, 0), 0) as remaining
      from public.diesel_entries diesel
      where diesel.petrol_pump_id = p_petrol_pump_id
        and coalesce(diesel.remaining_amount, 0) > 0
      order by diesel.entry_date, diesel.id
      for update
    loop
      exit when settlement_remaining <= 0;
      applied_to_diesel := least(diesel_row.remaining, settlement_remaining);

      update public.diesel_entries diesel
      set paid_amount = coalesce(diesel.paid_amount, 0) + applied_to_diesel,
          remaining_amount = greatest(
            coalesce(diesel.remaining_amount, 0) - applied_to_diesel,
            0
          ),
          payment_status = case
            when greatest(
              coalesce(diesel.remaining_amount, 0) - applied_to_diesel,
              0
            ) = 0 then 'Paid'
            else 'Partial'
          end
      where diesel.id = diesel_row.id;

      insert into public.petrol_pump_payment_allocations (
        payment_id,
        diesel_entry_id,
        amount
      ) values (
        payment_row.id,
        diesel_row.id,
        applied_to_diesel
      )
      on conflict (payment_id, diesel_entry_id)
      do update set amount = excluded.amount;

      settlement_remaining := settlement_remaining - applied_to_diesel;
    end loop;

    created_advance := greatest(settlement_remaining, 0);
    available_advance := greatest(
      available_advance - payment_row.advance_used,
      0
    ) + created_advance;

    current_payable := opening_outstanding + coalesce((
      select sum(greatest(coalesce(diesel.remaining_amount, 0), 0))
      from public.diesel_entries diesel
      where diesel.petrol_pump_id = p_petrol_pump_id
    ), 0);

    update public.petrol_pump_payments payment
    set amount = payment_row.advance_used + payment_row.payment_now,
        opening_applied = applied_to_opening,
        advance_created = created_advance,
        available_advance_before = advance_before,
        current_payable_before = payable_before,
        remaining_payable = current_payable,
        remaining_advance = available_advance,
        settlement_status = case
          when current_payable > 0 then 'Payable'
          when available_advance > 0 then 'Advance'
          else 'Paid'
        end,
        accounting_version = 1
    where payment.id = payment_row.id;

    if payment_row.payment_now = 0 then
      select cashbook.adda_id into existing_cashbook_adda from public.cashbook_entries cashbook
      where cashbook.reference_type='petrol_pump_payment' and cashbook.reference_id=payment_row.id::text for update;
      if found then
        if source_adda is null then
          raise exception using errcode='23514',message='PETROL_PAYMENT_AUTHORITATIVE_ADDA_UNRESOLVED';
        end if;
        perform public.ut_cashbook_assert_source_adda_id(existing_cashbook_adda,source_adda);
        delete from public.cashbook_entries cashbook where cashbook.reference_type='petrol_pump_payment' and cashbook.reference_id=payment_row.id::text;
      end if;
    else
      if source_adda is null then
        raise exception using errcode='23514',message='PETROL_PAYMENT_AUTHORITATIVE_ADDA_UNRESOLVED';
      end if;
      insert into public.cashbook_entries as existing_cashbook (
        entry_date,
        entry_type,
        person_type,
        person_name,
        vehicle_id,
        driver_id,
        loading_id,
        payment_method,
        amount,
        description,
        reference_type,
        reference_id,
        adda_id
      )
      select
        payment_row.payment_date,
        'Cash Out',
        'Petrol Pump',
        coalesce(pump.pump_name, 'Petrol Pump'),
        null,
        null,
        null,
        payment_row.payment_method,
        payment_row.payment_now,
        'Petrol pump payment: ' || coalesce(pump.pump_name, 'Petrol Pump'),
        'petrol_pump_payment',
        payment_row.id::text,
        source_adda
      from public.petrol_pumps pump
      where pump.id = p_petrol_pump_id
      on conflict (reference_type, reference_id)
        where reference_type = 'petrol_pump_payment'
          and reference_id is not null
      do update set
        adda_id = public.ut_cashbook_assert_source_adda_id(existing_cashbook.adda_id,excluded.adda_id),
        entry_date = excluded.entry_date,
        entry_type = excluded.entry_type,
        person_type = excluded.person_type,
        person_name = excluded.person_name,
        payment_method = excluded.payment_method,
        amount = excluded.amount,
        description = excluded.description;
    end if;
  end loop;

end
$function$;

create or replace function public.delete_petrol_pump_payment(
  p_payment_id bigint
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  pump_id uuid;
  source_adda uuid;
  existing_cashbook_adda uuid;
  reversal_row record;
begin
  select payment.petrol_pump_id
  into pump_id
  from public.petrol_pump_payments payment
  where payment.id = p_payment_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'payment_not_found';
  end if;

  source_adda := public.ut_validate_petrol_pump_payment_tenant(pump_id);
  perform pg_advisory_xact_lock(hashtextextended(pump_id::text, 0));
  perform set_config('ut.petrol_pump_payment_sync', 'on', true);
  perform set_config('ut.cashbook_sync', 'on', true);

  -- Normalize the chain first, then explicitly reverse the selected row's
  -- physical diesel effects before its cascading allocation evidence is lost.
  perform public.rebuild_petrol_pump_accounting(pump_id);
  for reversal_row in
    select allocation.diesel_entry_id, allocation.amount
    from public.petrol_pump_payment_allocations allocation
    where allocation.payment_id = p_payment_id
    for update
  loop
    if not exists (
      select 1
      from public.diesel_entries diesel
      where diesel.id = reversal_row.diesel_entry_id
        and coalesce(diesel.paid_amount, 0) >= reversal_row.amount
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'Recorded petrol pump allocation exceeds the diesel paid amount; delete stopped';
    end if;

    update public.diesel_entries diesel
    set paid_amount = coalesce(diesel.paid_amount, 0) - reversal_row.amount,
        remaining_amount = coalesce(diesel.remaining_amount, 0) + reversal_row.amount,
        payment_status = case
          when coalesce(diesel.paid_amount, 0) - reversal_row.amount <= 0
            then 'Unpaid'
          else 'Partial'
        end
    where diesel.id = reversal_row.diesel_entry_id;
  end loop;

  select cashbook.adda_id into existing_cashbook_adda from public.cashbook_entries cashbook
  where cashbook.reference_type='petrol_pump_payment' and cashbook.reference_id=p_payment_id::text for update;
  if found then
    perform public.ut_cashbook_assert_source_adda_id(existing_cashbook_adda,source_adda);
    delete from public.cashbook_entries cashbook where cashbook.reference_type='petrol_pump_payment' and cashbook.reference_id=p_payment_id::text;
  end if;
  delete from public.petrol_pump_payments payment
  where payment.id = p_payment_id;
  perform public.rebuild_petrol_pump_accounting(pump_id);
end
$function$;

create or replace function public.rebuild_oil_supplier_accounting(p_oil_shop_id uuid)
returns void
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  supplier_row record;
  payment_row record;
  bill_row record;
  v_opening numeric;
  v_advance numeric;
  v_opening_due numeric;
  v_payable numeric;
  v_advance_used numeric;
  v_settlement numeric;
  v_apply numeric;
  v_created numeric;
  v_cashbook_adda uuid;
begin
  select * into supplier_row
  from public.oil_shops
  where id=p_oil_shop_id and shop_type='external_supplier'
  for update;
  if not found then raise exception 'OIL_SUPPLIER_NOT_FOUND'; end if;
  if supplier_row.adda_id is null or not exists(select 1 from public.addas adda where adda.id=supplier_row.adda_id) then raise exception 'OIL_SUPPLIER_AUTHORITATIVE_ADDA_UNRESOLVED'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_oil_shop_id::text,0));
  perform set_config('ut.oil_supplier_sync','on',true);
  perform set_config('ut.cashbook_sync','on',true);

  delete from public.oil_supplier_payment_allocations allocation
  using public.oil_supplier_payments payment_source
  where allocation.payment_id=payment_source.id
    and payment_source.oil_shop_id=p_oil_shop_id;

  update public.oil_supplier_bills
  set paid_amount=0,remaining_amount=amount,payment_status='unpaid',updated_at=now()
  where oil_shop_id=p_oil_shop_id;

  v_opening:=coalesce(supplier_row.opening_balance,0);
  v_opening_due:=greatest(v_opening,0);
  v_advance:=greatest(-v_opening,0);

  for payment_row in
    select * from public.oil_supplier_payments
    where oil_shop_id=p_oil_shop_id
    order by payment_date,created_at,id
    for update
  loop
    select v_opening_due+coalesce(sum(remaining_amount),0)
      into v_payable
    from public.oil_supplier_bills
    where oil_shop_id=p_oil_shop_id;

    v_advance_used:=least(coalesce(payment_row.advance_used,0),v_advance,v_payable);
    v_settlement:=v_advance_used+coalesce(payment_row.payment_now,0);
    v_advance:=v_advance-v_advance_used;
    v_created:=0;

    v_apply:=least(v_settlement,v_opening_due);
    v_opening_due:=v_opening_due-v_apply;
    v_settlement:=v_settlement-v_apply;

    for bill_row in
      select * from public.oil_supplier_bills
      where oil_shop_id=p_oil_shop_id and remaining_amount>0
      order by bill_date,created_at,id
      for update
    loop
      exit when v_settlement<=0;
      v_apply:=least(v_settlement,bill_row.remaining_amount);
      insert into public.oil_supplier_payment_allocations(payment_id,supplier_bill_id,amount)
      values(payment_row.id,bill_row.id,v_apply);
      update public.oil_supplier_bills
      set paid_amount=paid_amount+v_apply,
          remaining_amount=remaining_amount-v_apply,
          payment_status=case when remaining_amount-v_apply=0 then 'paid' else 'partial' end,
          updated_at=now()
      where id=bill_row.id;
      v_settlement:=v_settlement-v_apply;
    end loop;

    if v_settlement>0 then
      v_created:=v_settlement;
      v_advance:=v_advance+v_settlement;
    end if;

    select v_opening_due+coalesce(sum(remaining_amount),0)
      into v_payable
    from public.oil_supplier_bills
    where oil_shop_id=p_oil_shop_id;

    update public.oil_supplier_payments
    set advance_used=v_advance_used,
        amount=v_advance_used+coalesce(payment_now,0),
        opening_applied=least(v_advance_used+coalesce(payment_now,0),greatest(v_opening,0)),
        advance_created=v_created,
        available_advance_before=v_advance+v_advance_used-v_created,
        current_payable_before=v_payable+(v_advance_used+coalesce(payment_now,0)-v_created),
        remaining_payable=v_payable,
        remaining_advance=v_advance,
        settlement_status=case when v_payable>0 then 'payable' when v_advance>0 then 'advance' else 'paid' end,
        accounting_version=1
    where id=payment_row.id;

    if coalesce(payment_row.payment_now,0)>0 then
      insert into public.cashbook_entries as existing_cashbook(
        entry_date,entry_type,person_type,person_name,payment_method,amount,
        description,reference_type,reference_id,adda_id
      ) values(
        payment_row.payment_date,'Cash Out','Other',supplier_row.shop_name,
        coalesce(nullif(payment_row.payment_method,''),'Cash'),payment_row.payment_now,
        'Oil supplier payment - '||supplier_row.shop_name,
        'oil_supplier_payment',payment_row.id::text,supplier_row.adda_id
      )
      on conflict(reference_type,reference_id)
      where reference_type='oil_supplier_payment' and reference_id is not null
      do update set
        adda_id=public.ut_cashbook_assert_source_adda_id(existing_cashbook.adda_id,excluded.adda_id),
        entry_date=excluded.entry_date,entry_type=excluded.entry_type,
        person_type=excluded.person_type,person_name=excluded.person_name,
        payment_method=excluded.payment_method,amount=excluded.amount,description=excluded.description;
    else
      select cashbook.adda_id into v_cashbook_adda from public.cashbook_entries cashbook
      where cashbook.reference_type='oil_supplier_payment' and cashbook.reference_id=payment_row.id::text for update;
      if found then
        perform public.ut_cashbook_assert_source_adda_id(v_cashbook_adda,supplier_row.adda_id);
        delete from public.cashbook_entries cashbook where cashbook.reference_type='oil_supplier_payment' and cashbook.reference_id=payment_row.id::text;
      end if;
    end if;
  end loop;
end
$$;

create or replace function public.delete_oil_supplier_payment(p_payment_id bigint) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_shop uuid;v_adda uuid;v_cashbook_adda uuid;begin select p.oil_shop_id,s.adda_id into v_shop,v_adda from public.oil_supplier_payments p join public.oil_shops s on s.id=p.oil_shop_id where p.id=p_payment_id for update;
if v_shop is null then raise exception 'PAYMENT_NOT_FOUND';end if;if auth.uid() is null or public.current_user_role() not in('super_admin','adda_admin','operator') or (not public.is_super_admin() and v_adda is distinct from public.current_user_adda_id()) then raise exception 'AUTHORIZATION_FAILED';end if;
if v_adda is null or not exists(select 1 from public.addas adda where adda.id=v_adda) then raise exception 'OIL_SUPPLIER_AUTHORITATIVE_ADDA_UNRESOLVED';end if;
perform set_config('ut.oil_supplier_sync','on',true);perform set_config('ut.cashbook_sync','on',true);
select cashbook.adda_id into v_cashbook_adda from public.cashbook_entries cashbook where cashbook.reference_type='oil_supplier_payment' and cashbook.reference_id=p_payment_id::text for update;
if found then perform public.ut_cashbook_assert_source_adda_id(v_cashbook_adda,v_adda);delete from public.cashbook_entries cashbook where cashbook.reference_type='oil_supplier_payment' and cashbook.reference_id=p_payment_id::text;end if;
delete from public.oil_supplier_payments where id=p_payment_id;perform public.rebuild_oil_supplier_accounting(v_shop);end $$;

create or replace function public.rebuild_tyre_shop_accounting(p_tyre_shop_id uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare supplier_row record;payment_row record;bill_row record;v_opening numeric;v_opening_due numeric;v_advance numeric;v_payable numeric;v_advance_used numeric;v_settlement numeric;v_apply numeric;v_created numeric;v_cashbook_adda uuid;
begin
 select * into supplier_row from public.tyre_shops where id=p_tyre_shop_id and shop_type='external_supplier' for update;if not found then raise exception 'TYRE_SHOP_NOT_FOUND';end if;if supplier_row.adda_id is null or not exists(select 1 from public.addas adda where adda.id=supplier_row.adda_id) then raise exception 'TYRE_SHOP_AUTHORITATIVE_ADDA_UNRESOLVED';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tyre_shop_id::text,0));perform set_config('ut.tyre_shop_sync','on',true);perform set_config('ut.cashbook_sync','on',true);
 delete from public.tyre_shop_payment_allocations allocation using public.tyre_shop_payments payment_source where allocation.payment_id=payment_source.id and payment_source.tyre_shop_id=p_tyre_shop_id;
 update public.tyre_shop_bills set paid_amount=0,remaining_amount=amount,payment_status='unpaid',updated_at=now() where tyre_shop_id=p_tyre_shop_id;
 v_opening:=coalesce(supplier_row.opening_balance,0);v_opening_due:=greatest(v_opening,0);v_advance:=greatest(-v_opening,0);
 for payment_row in select * from public.tyre_shop_payments where tyre_shop_id=p_tyre_shop_id order by payment_date,created_at,id for update loop
  select v_opening_due+coalesce(sum(remaining_amount),0) into v_payable from public.tyre_shop_bills where tyre_shop_id=p_tyre_shop_id;
  v_advance_used:=least(coalesce(payment_row.advance_used,0),v_advance,v_payable);v_settlement:=v_advance_used+coalesce(payment_row.payment_now,0);v_advance:=v_advance-v_advance_used;v_created:=0;
  v_apply:=least(v_settlement,v_opening_due);v_opening_due:=v_opening_due-v_apply;v_settlement:=v_settlement-v_apply;
  for bill_row in select * from public.tyre_shop_bills where tyre_shop_id=p_tyre_shop_id and remaining_amount>0 order by bill_date,created_at,id for update loop
   exit when v_settlement<=0;v_apply:=least(v_settlement,bill_row.remaining_amount);
   insert into public.tyre_shop_payment_allocations(payment_id,tyre_shop_bill_id,amount) values(payment_row.id,bill_row.id,v_apply);
   update public.tyre_shop_bills set paid_amount=paid_amount+v_apply,remaining_amount=remaining_amount-v_apply,payment_status=case when remaining_amount-v_apply=0 then 'paid' else 'partial' end,updated_at=now() where id=bill_row.id;v_settlement:=v_settlement-v_apply;
  end loop;
  if v_settlement>0 then v_created:=v_settlement;v_advance:=v_advance+v_settlement;end if;
  select v_opening_due+coalesce(sum(remaining_amount),0) into v_payable from public.tyre_shop_bills where tyre_shop_id=p_tyre_shop_id;
  update public.tyre_shop_payments set advance_used=v_advance_used,amount=v_advance_used+coalesce(payment_now,0),opening_applied=least(v_advance_used+coalesce(payment_now,0),greatest(v_opening,0)),advance_created=v_created,available_advance_before=v_advance+v_advance_used-v_created,current_payable_before=v_payable+(v_advance_used+coalesce(payment_now,0)-v_created),remaining_payable=v_payable,remaining_advance=v_advance,settlement_status=case when v_payable>0 then 'payable' when v_advance>0 then 'advance' else 'paid' end,accounting_version=1 where id=payment_row.id;
  if coalesce(payment_row.payment_now,0)>0 then insert into public.cashbook_entries as existing_cashbook(entry_date,entry_type,person_type,person_name,payment_method,amount,description,reference_type,reference_id,adda_id) values(payment_row.payment_date,'Cash Out','Other',supplier_row.shop_name,coalesce(nullif(payment_row.payment_method,''),'Cash'),payment_row.payment_now,'Tyre shop payment - '||supplier_row.shop_name,'tyre_shop_payment',payment_row.id::text,supplier_row.adda_id) on conflict(reference_type,reference_id) where reference_type='tyre_shop_payment' and reference_id is not null do update set adda_id=public.ut_cashbook_assert_source_adda_id(existing_cashbook.adda_id,excluded.adda_id),entry_date=excluded.entry_date,entry_type=excluded.entry_type,person_type=excluded.person_type,person_name=excluded.person_name,payment_method=excluded.payment_method,amount=excluded.amount,description=excluded.description;
  else select cashbook.adda_id into v_cashbook_adda from public.cashbook_entries cashbook where cashbook.reference_type='tyre_shop_payment' and cashbook.reference_id=payment_row.id::text for update;if found then perform public.ut_cashbook_assert_source_adda_id(v_cashbook_adda,supplier_row.adda_id);delete from public.cashbook_entries cashbook where cashbook.reference_type='tyre_shop_payment' and cashbook.reference_id=payment_row.id::text;end if;end if;
 end loop;
end $$;

create or replace function public.save_tyre_shop_payment(
  p_payment_id bigint,
  p_tyre_shop_id uuid,
  p_payment_date date,
  p_advance_used numeric,
  p_payment_now numeric,
  p_payment_method text,
  p_reference_no text,
  p_remarks text
)
returns bigint
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_id bigint;
  v_adda uuid;
  v_shop_name text;

  v_advance numeric:=
    coalesce(p_advance_used,0);

  v_now numeric:=
    coalesce(p_payment_now,0);
begin
  if auth.uid() is null
     or public.current_user_role() not in (
       'super_admin',
       'adda_admin',
       'operator'
     )
  then
    raise exception 'AUTHORIZATION_FAILED';
  end if;

  select
    shop.adda_id,
    shop.shop_name
  into
    v_adda,
    v_shop_name
  from public.tyre_shops shop
  where shop.id=p_tyre_shop_id
    and shop.shop_type='external_supplier';

  if v_adda is null then
    raise exception 'TYRE_SHOP_NOT_FOUND';
  end if;

  if not public.is_super_admin()
     and v_adda is distinct from public.current_user_adda_id()
  then
    raise exception 'TENANT_MISMATCH';
  end if;

  if p_payment_date is null
     or v_advance<0
     or v_now<0
     or v_advance+v_now<=0
  then
    raise exception 'INVALID_PAYMENT';
  end if;

  perform set_config(
    'ut.tyre_shop_sync',
    'on',
    true
  );

  if p_payment_id is null then

    insert into public.tyre_shop_payments(
      tyre_shop_id,
      payment_date,
      amount,
      advance_used,
      payment_now,
      payment_method,
      reference_no,
      remarks
    )
    values(
      p_tyre_shop_id,
      p_payment_date,
      v_advance+v_now,
      v_advance,
      v_now,
      nullif(btrim(p_payment_method),''),
      nullif(btrim(p_reference_no),''),
      nullif(btrim(p_remarks),'')
    )
    returning id into v_id;

  else

    select payment.id
    into v_id
    from public.tyre_shop_payments payment
    where payment.id=p_payment_id
      and payment.tyre_shop_id=p_tyre_shop_id
    for update;

    if v_id is null then
      raise exception
        'PAYMENT_NOT_FOUND_OR_SUPPLIER_CHANGE';
    end if;

    update public.tyre_shop_payments
    set
      payment_date=p_payment_date,
      amount=v_advance+v_now,
      advance_used=v_advance,
      payment_now=v_now,
      payment_method=
        nullif(btrim(p_payment_method),''),
      reference_no=
        nullif(btrim(p_reference_no),''),
      remarks=
        nullif(btrim(p_remarks),'')
    where id=v_id;

  end if;

  perform public.rebuild_tyre_shop_accounting(
    p_tyre_shop_id
  );

  return v_id;
end
$function$;

create or replace function public.delete_tyre_shop_payment(p_payment_id bigint) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_shop uuid;v_adda uuid;v_cashbook_adda uuid;begin select payment_row.tyre_shop_id,shop.adda_id into v_shop,v_adda from public.tyre_shop_payments payment_row join public.tyre_shops shop on shop.id=payment_row.tyre_shop_id where payment_row.id=p_payment_id for update;if v_shop is null then raise exception 'PAYMENT_NOT_FOUND';end if;if auth.uid() is null or public.current_user_role() not in('super_admin','adda_admin','operator') or(not public.is_super_admin() and v_adda is distinct from public.current_user_adda_id()) then raise exception 'AUTHORIZATION_FAILED';end if;if v_adda is null or not exists(select 1 from public.addas adda where adda.id=v_adda) then raise exception 'TYRE_SHOP_AUTHORITATIVE_ADDA_UNRESOLVED';end if;perform set_config('ut.tyre_shop_sync','on',true);perform set_config('ut.cashbook_sync','on',true);select cashbook.adda_id into v_cashbook_adda from public.cashbook_entries cashbook where cashbook.reference_type='tyre_shop_payment' and cashbook.reference_id=p_payment_id::text for update;if found then perform public.ut_cashbook_assert_source_adda_id(v_cashbook_adda,v_adda);delete from public.cashbook_entries cashbook where cashbook.reference_type='tyre_shop_payment' and cashbook.reference_id=p_payment_id::text;end if;delete from public.tyre_shop_payments where id=p_payment_id;perform public.rebuild_tyre_shop_accounting(v_shop);end $$;
-- Preserve each routine's pre-migration effective service_role access only when it already existed.
do $preserve_service_role$
declare target_signature text;
begin
  for target_signature in
    select signature from (values
      ('public.ut_validate_petrol_pump_payment_tenant(uuid)'),
      ('public.rebuild_petrol_pump_accounting(uuid)'),
      ('public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'),
      ('public.delete_petrol_pump_payment(bigint)'),
      ('public.rebuild_oil_supplier_accounting(uuid)'),
      ('public.save_oil_supplier_payment(bigint,uuid,date,numeric,numeric,text,text,text)'),
      ('public.delete_oil_supplier_payment(bigint)'),
      ('public.rebuild_tyre_shop_accounting(uuid)'),
      ('public.save_tyre_shop_payment(bigint,uuid,date,numeric,numeric,text,text,text)'),
      ('public.delete_tyre_shop_payment(bigint)')
    ) expected(signature)
  loop
    if has_function_privilege('service_role',to_regprocedure(target_signature),'EXECUTE') then
      execute format('grant execute on function %s to service_role',target_signature);
    end if;
  end loop;
end
$preserve_service_role$;
-- Private accounting/tenant primitives: remove browser execution and preserve any pre-existing service_role access.
revoke all on function public.ut_validate_petrol_pump_payment_tenant(uuid), public.rebuild_petrol_pump_accounting(uuid), public.rebuild_oil_supplier_accounting(uuid), public.rebuild_tyre_shop_accounting(uuid) from public, anon, authenticated;
-- Keep approved save/delete RPCs authenticated-callable; remove only PUBLIC/anon exposure.
revoke all on function public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text), public.delete_petrol_pump_payment(bigint), public.save_oil_supplier_payment(bigint,uuid,date,numeric,numeric,text,text,text), public.delete_oil_supplier_payment(bigint), public.save_tyre_shop_payment(bigint,uuid,date,numeric,numeric,text,text,text), public.delete_tyre_shop_payment(bigint) from public, anon;
grant execute on function public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text), public.delete_petrol_pump_payment(bigint), public.save_oil_supplier_payment(bigint,uuid,date,numeric,numeric,text,text,text), public.delete_oil_supplier_payment(bigint), public.save_tyre_shop_payment(bigint,uuid,date,numeric,numeric,text,text,text), public.delete_tyre_shop_payment(bigint) to authenticated;
commit;
