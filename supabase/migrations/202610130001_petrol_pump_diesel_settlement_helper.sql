BEGIN;

DO $preflight$
DECLARE
  rebuild_oid oid:=pg_catalog.to_regprocedure(
    'public.rebuild_petrol_pump_accounting(uuid)'
  );
  payment_writer_oid oid:=pg_catalog.to_regprocedure(
    'public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'
  );
  manual_writer_oid oid:=pg_catalog.to_regprocedure(
    'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
  );
  rebuild_config text;
BEGIN
  IF EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc procedure_row
       WHERE procedure_row.proname='recalculate_petrol_pump_diesel_settlement'
         AND procedure_row.pronargs=1
         AND pg_catalog.pg_get_function_identity_arguments(procedure_row.oid)='uuid'
     ) THEN
    RAISE EXCEPTION 'PUMP_DIESEL_SETTLEMENT_HELPER_ALREADY_EXISTS';
  END IF;

  IF rebuild_oid IS NULL OR payment_writer_oid IS NULL OR manual_writer_oid IS NULL THEN
    RAISE EXCEPTION 'PUMP_DIESEL_SETTLEMENT_REQUIRED_ROUTINE_MISSING';
  END IF;

  SELECT pg_catalog.regexp_replace(lower(coalesce(procedure_row.proconfig::text,'')),
    '[{}," ]','','g')
    INTO rebuild_config
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid=rebuild_oid
    AND procedure_row.prosecdef
    AND procedure_row.provolatile='v'
    AND procedure_row.prosrc ILIKE '%petrol_pump_payment_allocations%'
    AND procedure_row.prosrc ILIKE '%cashbook_entries%';
  IF rebuild_config IS NULL
     OR rebuild_config NOT IN('search_path=publicpg_temp','search_path=') THEN
    RAISE EXCEPTION 'PUMP_DIESEL_SETTLEMENT_REBUILD_CONTRACT_DRIFT';
  END IF;

  IF NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc procedure_row
       WHERE procedure_row.oid=payment_writer_oid
         AND procedure_row.prosecdef
         AND procedure_row.prosrc ILIKE '%rebuild_petrol_pump_accounting%'
         AND procedure_row.proowner=(SELECT rebuild_row.proowner
           FROM pg_catalog.pg_proc rebuild_row WHERE rebuild_row.oid=rebuild_oid)
     ) OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc procedure_row
       WHERE procedure_row.oid=manual_writer_oid
         AND procedure_row.prosecdef
         AND procedure_row.prosrc ILIKE '%save_petrol_pump_payment%'
     ) THEN
    RAISE EXCEPTION 'PUMP_DIESEL_SETTLEMENT_PAYMENT_CHAIN_DRIFT';
  END IF;

  IF NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc procedure_row
       WHERE procedure_row.prokind='f'
         AND procedure_row.prosrc ILIKE '%recalculate_petrol_pump_diesel_settlement%'
     ) THEN
    RAISE EXCEPTION 'PUMP_DIESEL_SETTLEMENT_STALE_CALLER_NOT_FOUND';
  END IF;

  IF NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_trigger trigger_row
       JOIN pg_catalog.pg_class relation_row ON relation_row.oid=trigger_row.tgrelid
       JOIN pg_catalog.pg_namespace relation_namespace
         ON relation_namespace.oid=relation_row.relnamespace
       JOIN pg_catalog.pg_proc callback_row ON callback_row.oid=trigger_row.tgfoid
       JOIN pg_catalog.pg_namespace callback_namespace
         ON callback_namespace.oid=callback_row.pronamespace
       WHERE relation_namespace.nspname='public'
         AND relation_row.relname='petrol_pump_payments'
         AND trigger_row.tgname='diesel_settlement_after_pump_payment_change'
         AND NOT trigger_row.tgisinternal
         AND trigger_row.tgenabled<>'D'
         AND callback_namespace.nspname='public'
         AND callback_row.proname='trigger_recalculate_petrol_pump_settlement'
         AND callback_row.prosrc ILIKE '%recalculate_petrol_pump_diesel_settlement%'
         AND (
           (callback_row.prosecdef AND callback_row.proowner=(
             SELECT rebuild_row.proowner FROM pg_catalog.pg_proc rebuild_row
             WHERE rebuild_row.oid=rebuild_oid))
           OR (NOT callback_row.prosecdef AND callback_row.proowner=(
             SELECT payment_row.proowner FROM pg_catalog.pg_proc payment_row
             WHERE payment_row.oid=payment_writer_oid))
         )
     ) THEN
    RAISE EXCEPTION 'PUMP_DIESEL_SETTLEMENT_PAYMENT_TRIGGER_DRIFT';
  END IF;
END
$preflight$;

-- Replace only stale helper-name references in existing function bodies.
-- pg_get_functiondef preserves each caller's signature, security, search_path,
-- owner, and grants; only the called routine name changes.
DO $patch_callers$
DECLARE
  caller_row record;
  caller_definition text;
  patched_definition text;
  patched_count integer:=0;
  original_owner oid;
  original_secdef boolean;
  original_volatility text;
  original_config text[];
  original_acl text;
  patched_owner oid;
  patched_secdef boolean;
  patched_volatility text;
  patched_config text[];
  patched_acl text;
BEGIN
  FOR caller_row IN
    SELECT procedure_row.oid,procedure_row.proowner,procedure_row.prosecdef,
           procedure_row.provolatile::text AS provolatile,procedure_row.proconfig,
           procedure_row.proacl::text AS proacl
    FROM pg_catalog.pg_proc procedure_row
    WHERE procedure_row.prokind='f'
      AND procedure_row.prosrc ILIKE '%recalculate_petrol_pump_diesel_settlement%'
    ORDER BY procedure_row.oid
  LOOP
    original_owner:=caller_row.proowner;
    original_secdef:=caller_row.prosecdef;
    original_volatility:=caller_row.provolatile;
    original_config:=caller_row.proconfig;
    original_acl:=caller_row.proacl;
    caller_definition:=pg_catalog.pg_get_functiondef(caller_row.oid);
    patched_definition:=pg_catalog.regexp_replace(
      caller_definition,
      '([[:alnum:]_]+[.])?recalculate_petrol_pump_diesel_settlement',
      'public.rebuild_petrol_pump_accounting',
      'gi'
    );
    IF patched_definition=caller_definition
       OR patched_definition ILIKE '%recalculate_petrol_pump_diesel_settlement%' THEN
      RAISE EXCEPTION 'PUMP_DIESEL_SETTLEMENT_CALLER_PATCH_UNSAFE: %',caller_row.oid::regprocedure;
    END IF;
    EXECUTE patched_definition;
    SELECT procedure_row.proowner,procedure_row.prosecdef,
           procedure_row.provolatile::text,procedure_row.proconfig,procedure_row.proacl::text
    INTO patched_owner,patched_secdef,patched_volatility,patched_config,patched_acl
    FROM pg_catalog.pg_proc procedure_row
    WHERE procedure_row.oid=caller_row.oid;
    IF patched_owner IS DISTINCT FROM original_owner
       OR patched_secdef IS DISTINCT FROM original_secdef
       OR patched_volatility IS DISTINCT FROM original_volatility
       OR patched_config IS DISTINCT FROM original_config
       OR patched_acl IS DISTINCT FROM original_acl THEN
      RAISE EXCEPTION 'PUMP_DIESEL_SETTLEMENT_CALLER_SECURITY_CHANGED: %',caller_row.oid::regprocedure;
    END IF;
    patched_count:=patched_count+1;
  END LOOP;

  IF patched_count=0 THEN
    RAISE EXCEPTION 'PUMP_DIESEL_SETTLEMENT_NO_CALLERS_PATCHED';
  END IF;
END
$patch_callers$;

COMMIT;
