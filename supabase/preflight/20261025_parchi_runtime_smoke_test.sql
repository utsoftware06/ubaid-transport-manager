-- WRITE TEST ONLY. Run against a disposable/staging database, never production.
-- Setup reads existing fixtures as the SQL session's admin role. Assertions run
-- after SET LOCAL ROLE authenticated and use the JWT claims of real active
-- profiles selected below. No table, trigger, or production business row is
-- bypassed or modified directly. All test rows are rolled back at the end.
-- PostgreSQL sequences are non-transactional: generated ID/Parchi-number gaps
-- may remain even though all inserted test rows are rolled back.
-- The local claims exercise auth.uid()/auth.role() for real profile IDs; this
-- does not validate signed-token issuance or HTTP/PostgREST transport.
-- Single-session execution does not test concurrent caps/idempotency races.

BEGIN;

CREATE TEMP TABLE parchi_smoke_fixture (
  operator_id uuid,
  adda_id uuid,
  broker_id uuid,
  other_adda_id uuid,
  admin_id uuid,
  other_tenant_adda_id uuid,
  setup_note text
) ON COMMIT PRESERVE ROWS;

CREATE TEMP TABLE parchi_smoke_results (
  test_name text PRIMARY KEY,
  result text NOT NULL CHECK (result IN ('PASS','FAIL','SKIP')),
  details text NOT NULL
) ON COMMIT PRESERVE ROWS;

-- CREATE TEMP TABLE above initializes this session's real pg_temp_N schema.
-- `pg_temp` is a relation-lookup alias, not a grantable schema name. Resolve
-- the actual temporary namespace instead of hard-coding a session-specific
-- pg_temp_N name.
DO $grant_temp_schema_usage$
DECLARE
  v_temp_schema name;
BEGIN
  SELECT namespace_row.nspname INTO STRICT v_temp_schema
  FROM pg_catalog.pg_namespace AS namespace_row
  WHERE namespace_row.oid=pg_catalog.pg_my_temp_schema();

  EXECUTE pg_catalog.format('GRANT USAGE ON SCHEMA %I TO authenticated',v_temp_schema);
END;
$grant_temp_schema_usage$;

-- Fixture discovery runs as the database administrator. IDs are selected from
-- existing rows; this script does not invent tenant or counterparty IDs.
INSERT INTO pg_temp.parchi_smoke_fixture
  (operator_id,adda_id,broker_id,other_adda_id,admin_id,other_tenant_adda_id,setup_note)
SELECT operator_profile.id,
       operator_profile.adda_id,
       broker.id,
       other_adda.id,
       admin_profile.id,
       other_tenant.id,
       'Existing active operator selected; absent optional fixtures are reported as SKIP.'
FROM public.profiles AS operator_profile
JOIN public.addas AS own_adda ON own_adda.id=operator_profile.adda_id
LEFT JOIN LATERAL (
  SELECT broker_row.id
  FROM public.brokers AS broker_row
  WHERE broker_row.adda_id=operator_profile.adda_id
  ORDER BY broker_row.id
  LIMIT 1
) AS broker ON true
LEFT JOIN LATERAL (
  SELECT other_adda_row.id
  FROM public.other_addas AS other_adda_row
  WHERE other_adda_row.adda_id=operator_profile.adda_id
    AND other_adda_row.status='active'
  ORDER BY other_adda_row.id
  LIMIT 1
) AS other_adda ON true
LEFT JOIN LATERAL (
  SELECT admin_row.id
  FROM public.profiles AS admin_row
  WHERE admin_row.adda_id=operator_profile.adda_id
    AND admin_row.role='adda_admin' AND admin_row.is_active=true
  ORDER BY admin_row.id
  LIMIT 1
) AS admin_profile ON true
LEFT JOIN LATERAL (
  SELECT adda_row.id
  FROM public.addas AS adda_row
  WHERE adda_row.id IS DISTINCT FROM operator_profile.adda_id
  ORDER BY adda_row.id
  LIMIT 1
) AS other_tenant ON true
WHERE operator_profile.role='operator'
  AND operator_profile.is_active=true
  AND operator_profile.adda_id IS NOT NULL
ORDER BY (broker.id IS NOT NULL AND other_adda.id IS NOT NULL) DESC,
         (broker.id IS NOT NULL) DESC,
         (other_adda.id IS NOT NULL) DESC,
         operator_profile.adda_id,operator_profile.id
LIMIT 1;

INSERT INTO pg_temp.parchi_smoke_fixture (setup_note)
SELECT 'SKIP: no active operator profile with an assigned Adda exists.'
WHERE NOT EXISTS (SELECT 1 FROM pg_temp.parchi_smoke_fixture);

GRANT SELECT ON TABLE pg_temp.parchi_smoke_fixture TO authenticated;
GRANT SELECT,INSERT ON TABLE pg_temp.parchi_smoke_results TO authenticated;

-- Authorization assertions run as the actual database role `authenticated`.
-- JWT claim settings name a real active profile selected from public.profiles.
SET LOCAL ROLE authenticated;

DO $parchi_smoke$
DECLARE
  fixture_row record;
  v_doc_date date:=CURRENT_DATE;
  v_funding_due date:=CURRENT_DATE+7;
  v_settlement_due date:=CURRENT_DATE+30;
  v_req_create uuid;
  v_req_funding uuid;
  v_req_settlement uuid;
  v_req_reverse uuid;
  v_received_id uuid;
  v_issued_id uuid;
  v_cancel_id uuid;
  v_received_funding_id uuid;
  v_issued_funding_id uuid;
  v_received_settlement_id uuid;
  v_issued_settlement_id uuid;
  v_received_reversal_id uuid;
  v_issued_reversal_id uuid;
  v_returned_id uuid;
  v_retry_id uuid;
  v_request_count bigint;
  v_cashbook_count bigint;
  v_row_count bigint;
  v_net_funded numeric;
  v_net_settled numeric;
  v_balance numeric;
  v_funding_status text;
  v_settlement_status text;
  v_state text;
  v_message text;
  v_fake_event_id uuid;
BEGIN
  SELECT * INTO fixture_row FROM pg_temp.parchi_smoke_fixture LIMIT 1;

  IF fixture_row.operator_id IS NULL THEN
    INSERT INTO pg_temp.parchi_smoke_results VALUES
      ('FIXTURES','SKIP',fixture_row.setup_note),
      ('RECEIVED_FLOW','SKIP','Requires an active operator and an existing Broker owned by that operator Adda.'),
      ('ISSUED_FLOW','SKIP','Requires an active operator and an active Other Adda owned by that operator Adda.'),
      ('LIMITS_IDEMPOTENCY','SKIP','No authorized operator fixture.'),
      ('REVERSALS','SKIP','No authorized operator fixture.'),
      ('ADMIN_MUTATIONS','SKIP','No authorized operator fixture.'),
      ('CANCELLATION','SKIP','No authorized operator fixture.'),
      ('CROSS_TENANT','SKIP','No authorized operator fixture.'),
      ('CASHBOOK_PROTECTION','SKIP','No authorized operator fixture.'),
      ('DIRECT_TABLE_DML','SKIP','No authorized operator fixture.');
    RETURN;
  END IF;

  PERFORM pg_catalog.set_config('request.jwt.claims',
    pg_catalog.jsonb_build_object('sub',fixture_row.operator_id::text,
      'role','authenticated','aud','authenticated')::text,true);
  PERFORM pg_catalog.set_config('request.jwt.claim.sub',fixture_row.operator_id::text,true);
  PERFORM pg_catalog.set_config('request.jwt.claim.role','authenticated',true);

  INSERT INTO pg_temp.parchi_smoke_results VALUES
    ('FIXTURES','PASS',pg_catalog.concat('operator=',fixture_row.operator_id,
      '; adda=',fixture_row.adda_id,'; broker=',COALESCE(fixture_row.broker_id::text,'missing'),
      '; active_other_adda=',COALESCE(fixture_row.other_adda_id::text,'missing'),
      '; adda_admin=',COALESCE(fixture_row.admin_id::text,'missing'),
      '; second_adda=',COALESCE(fixture_row.other_tenant_adda_id::text,'missing')));

  -- Received Parchi: document, partial funding, partial repayment, retries and limits.
  IF fixture_row.broker_id IS NULL THEN
    INSERT INTO pg_temp.parchi_smoke_results VALUES
      ('RECEIVED_FLOW','SKIP','No existing Broker belongs to the selected operator Adda.'),
      ('RECEIVED_LIMITS_IDEMPOTENCY','SKIP','Received flow requires a same-Adda Broker.'),
      ('CROSS_ACTION_REQUEST_REUSE_REJECTED','SKIP','Received flow requires a same-Adda Broker.');
  ELSE
    BEGIN
      v_req_create:=pg_catalog.gen_random_uuid();
      v_received_id:=public.create_parchi(
        fixture_row.adda_id,'received',fixture_row.broker_id,NULL,v_doc_date,1000.00,
        v_funding_due,v_settlement_due,'SMOKE-RECEIVED','transaction rollback smoke test',
        NULL,NULL,NULL,NULL,NULL,NULL,v_req_create);
      v_retry_id:=public.create_parchi(
        fixture_row.adda_id,'received',fixture_row.broker_id,NULL,v_doc_date,1000.00,
        v_funding_due,v_settlement_due,'SMOKE-RECEIVED','transaction rollback smoke test',
        NULL,NULL,NULL,NULL,NULL,NULL,v_req_create);
      SELECT pg_catalog.count(*) INTO v_request_count
      FROM public.parchi_events AS event_row
      WHERE event_row.adda_id=fixture_row.adda_id AND event_row.request_id=v_req_create;
      SELECT pg_catalog.count(*) INTO v_cashbook_count
      FROM public.cashbook_entries AS cashbook
      JOIN public.parchi_events AS event_row ON event_row.id::text=cashbook.reference_id
      WHERE cashbook.reference_type='parchi_event' AND event_row.parchi_id=v_received_id;
      IF v_received_id=v_retry_id AND v_request_count=1 THEN
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('RECEIVED_CREATE_IDEMPOTENCY','PASS',
          'Identical create retry returned the same Parchi; one creation event exists.');
      ELSE
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('RECEIVED_CREATE_IDEMPOTENCY','FAIL',
          pg_catalog.concat('same_id=',v_received_id=v_retry_id,'; request_events=',v_request_count));
      END IF;
      IF v_cashbook_count=0 THEN
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('RECEIVED_UNFUNDED_NO_CASHBOOK','PASS',
          'Document creation posted no money event or Cashbook row.');
      ELSE
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('RECEIVED_UNFUNDED_NO_CASHBOOK','FAIL',
          pg_catalog.concat('cashbook_rows=',v_cashbook_count));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
      v_received_id:=NULL;
      INSERT INTO pg_temp.parchi_smoke_results VALUES ('RECEIVED_CREATE_IDEMPOTENCY','FAIL',
        pg_catalog.concat(v_state,': ',v_message)),
        ('RECEIVED_UNFUNDED_NO_CASHBOOK','SKIP','Received document creation did not complete.');
    END;

    IF v_received_id IS NOT NULL THEN
      BEGIN
        v_req_funding:=pg_catalog.gen_random_uuid();
        v_received_funding_id:=public.post_parchi_funding(
          v_received_id,v_doc_date,400.00,'Cash','SMOKE-R-FUND',v_req_funding);
        v_retry_id:=public.post_parchi_funding(
          v_received_id,v_doc_date,400.00,'Cash','SMOKE-R-FUND',v_req_funding);
        SELECT pg_catalog.count(*) INTO v_request_count FROM public.parchi_events
        WHERE adda_id=fixture_row.adda_id AND request_id=v_req_funding;
        SELECT pg_catalog.count(*) INTO v_cashbook_count FROM public.cashbook_entries
        WHERE reference_type='parchi_event' AND reference_id=v_received_funding_id::text
          AND adda_id=fixture_row.adda_id AND entry_type='Cash In' AND amount=400.00;
        IF v_received_funding_id=v_retry_id AND v_request_count=1 AND v_cashbook_count=1 THEN
          INSERT INTO pg_temp.parchi_smoke_results VALUES ('RECEIVED_PARTIAL_FUNDING_RETRY','PASS',
            'Rs 400 funding is Cash In; identical retry has one event and one Cashbook row.');
        ELSE
          INSERT INTO pg_temp.parchi_smoke_results VALUES ('RECEIVED_PARTIAL_FUNDING_RETRY','FAIL',
            pg_catalog.concat('same_id=',v_received_funding_id=v_retry_id,
              '; request_events=',v_request_count,'; matching_cashbook=',v_cashbook_count));
        END IF;
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
        v_received_funding_id:=NULL;
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('RECEIVED_PARTIAL_FUNDING_RETRY','FAIL',
          pg_catalog.concat(v_state,': ',v_message));
      END;

      IF v_received_funding_id IS NULL THEN
        INSERT INTO pg_temp.parchi_smoke_results VALUES
          ('RECEIVED_OVERFUNDING_REJECTED','SKIP','Partial funding did not complete.'),
          ('CROSS_ACTION_REQUEST_REUSE_REJECTED','SKIP','Partial funding did not complete.'),
          ('RECEIVED_OVERSETTLEMENT_REJECTED','SKIP','Partial funding did not complete.'),
          ('RECEIVED_PARTIAL_SETTLEMENT_STATUS','SKIP','Partial funding did not complete.');
      ELSE
      BEGIN
        PERFORM public.post_parchi_funding(
          v_received_id,v_doc_date,601.00,'Cash','SMOKE-R-OVER',pg_catalog.gen_random_uuid());
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('RECEIVED_OVERFUNDING_REJECTED','FAIL',
          'Overfunding was accepted.');
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('RECEIVED_OVERFUNDING_REJECTED',
          CASE WHEN v_message='PARCHI_FUNDING_EXCEEDS_DOCUMENT_AMOUNT' THEN 'PASS' ELSE 'FAIL' END,
          pg_catalog.concat(v_state,': ',v_message));
      END;

      BEGIN
        PERFORM public.post_parchi_settlement(
          v_received_id,v_doc_date,1.00,'Cash','SMOKE-R-CROSS-ACTION',v_req_funding);
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('CROSS_ACTION_REQUEST_REUSE_REJECTED','FAIL',
          'Funding request UUID was accepted by a different action.');
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('CROSS_ACTION_REQUEST_REUSE_REJECTED',
          CASE WHEN v_message='PARCHI_IDEMPOTENCY_PAYLOAD_MISMATCH' THEN 'PASS' ELSE 'FAIL' END,
          pg_catalog.concat(v_state,': ',v_message));
      END;

      BEGIN
        PERFORM public.post_parchi_settlement(
          v_received_id,v_doc_date,401.00,'Cash','SMOKE-R-OVER-SETTLE',pg_catalog.gen_random_uuid());
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('RECEIVED_OVERSETTLEMENT_REJECTED','FAIL',
          'Settlement above funded amount was accepted.');
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('RECEIVED_OVERSETTLEMENT_REJECTED',
          CASE WHEN v_message='PARCHI_SETTLEMENT_EXCEEDS_FUNDED_OUTSTANDING_AS_OF_DATE' THEN 'PASS' ELSE 'FAIL' END,
          pg_catalog.concat(v_state,': ',v_message));
      END;

      BEGIN
        v_req_settlement:=pg_catalog.gen_random_uuid();
        v_received_settlement_id:=public.post_parchi_settlement(
          v_received_id,v_doc_date,150.00,'Cash','SMOKE-R-SETTLE',v_req_settlement);
        v_retry_id:=public.post_parchi_settlement(
          v_received_id,v_doc_date,150.00,'Cash','SMOKE-R-SETTLE',v_req_settlement);
        SELECT pg_catalog.count(*) INTO v_request_count FROM public.parchi_events
        WHERE adda_id=fixture_row.adda_id AND request_id=v_req_settlement;
        SELECT net_funded,net_settled,funded_outstanding,funding_status,settlement_status
          INTO v_net_funded,v_net_settled,v_balance,v_funding_status,v_settlement_status
        FROM public.get_parchi_statement(fixture_row.adda_id,'broker',fixture_row.broker_id)
        WHERE parchi_id=v_received_id LIMIT 1;
        SELECT pg_catalog.count(*) INTO v_cashbook_count FROM public.cashbook_entries
        WHERE reference_type='parchi_event' AND reference_id=v_received_settlement_id::text
          AND adda_id=fixture_row.adda_id AND entry_type='Cash Out' AND amount=150.00;
        IF v_received_settlement_id=v_retry_id AND v_request_count=1 AND v_cashbook_count=1
           AND v_net_funded=400.00 AND v_net_settled=150.00 AND v_balance=250.00
           AND v_funding_status='Partially Funded' AND v_settlement_status='Partially Settled' THEN
          INSERT INTO pg_temp.parchi_smoke_results VALUES ('RECEIVED_PARTIAL_SETTLEMENT_STATUS','PASS',
            'Funded 400, repaid 150, outstanding 250, partially settled; repayment is Cash Out; retry is idempotent.');
        ELSE
          INSERT INTO pg_temp.parchi_smoke_results VALUES ('RECEIVED_PARTIAL_SETTLEMENT_STATUS','FAIL',
            pg_catalog.concat('funded=',v_net_funded,' settled=',v_net_settled,' outstanding=',v_balance,
              ' funding_status=',v_funding_status,' settlement_status=',v_settlement_status,
              ' retry_same=',v_received_settlement_id=v_retry_id,' events=',v_request_count,
              ' cashbook=',v_cashbook_count));
        END IF;
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
        v_received_settlement_id:=NULL;
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('RECEIVED_PARTIAL_SETTLEMENT_STATUS','FAIL',
          pg_catalog.concat(v_state,': ',v_message));
      END;
      END IF;
    ELSE
      INSERT INTO pg_temp.parchi_smoke_results VALUES
        ('RECEIVED_PARTIAL_FUNDING_RETRY','SKIP','Received Parchi creation failed.'),
        ('RECEIVED_OVERFUNDING_REJECTED','SKIP','Received Parchi creation failed.'),
        ('CROSS_ACTION_REQUEST_REUSE_REJECTED','SKIP','Received Parchi creation failed.'),
        ('RECEIVED_OVERSETTLEMENT_REJECTED','SKIP','Received Parchi creation failed.'),
        ('RECEIVED_PARTIAL_SETTLEMENT_STATUS','SKIP','Received Parchi creation failed.');
    END IF;
  END IF;

  -- Issued Parchi: funding is Cash Out; recovery is Cash In.
  IF fixture_row.other_adda_id IS NULL THEN
    INSERT INTO pg_temp.parchi_smoke_results VALUES
      ('ISSUED_FLOW','SKIP','No active Other Adda belongs to the selected operator Adda.'),
      ('ISSUED_LIMITS_IDEMPOTENCY','SKIP','Issued flow requires a same-Adda active Other Adda.');
  ELSE
    BEGIN
      v_req_create:=pg_catalog.gen_random_uuid();
      v_issued_id:=public.create_parchi(
        fixture_row.adda_id,'issued',NULL,fixture_row.other_adda_id,v_doc_date,1000.00,
        v_funding_due,v_settlement_due,'SMOKE-ISSUED','transaction rollback smoke test',
        NULL,NULL,NULL,NULL,NULL,NULL,v_req_create);
      v_retry_id:=public.create_parchi(
        fixture_row.adda_id,'issued',NULL,fixture_row.other_adda_id,v_doc_date,1000.00,
        v_funding_due,v_settlement_due,'SMOKE-ISSUED','transaction rollback smoke test',
        NULL,NULL,NULL,NULL,NULL,NULL,v_req_create);
      SELECT pg_catalog.count(*) INTO v_cashbook_count
      FROM public.cashbook_entries AS cashbook
      JOIN public.parchi_events AS event_row ON event_row.id::text=cashbook.reference_id
      WHERE cashbook.reference_type='parchi_event' AND event_row.parchi_id=v_issued_id;
      IF v_issued_id=v_retry_id AND v_cashbook_count=0 THEN
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('ISSUED_CREATE_NO_INITIAL_CASHBOOK','PASS',
          'Identical create retry returned the original Parchi; unfunded Issued document has no Cashbook row.');
      ELSE
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('ISSUED_CREATE_NO_INITIAL_CASHBOOK','FAIL',
          pg_catalog.concat('same_id=',v_issued_id=v_retry_id,'; cashbook_rows=',v_cashbook_count));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
      v_issued_id:=NULL;
      INSERT INTO pg_temp.parchi_smoke_results VALUES ('ISSUED_CREATE_NO_INITIAL_CASHBOOK','FAIL',
        pg_catalog.concat(v_state,': ',v_message));
    END;

    IF v_issued_id IS NOT NULL THEN
      BEGIN
        v_req_funding:=pg_catalog.gen_random_uuid();
        v_issued_funding_id:=public.post_parchi_funding(
          v_issued_id,v_doc_date,400.00,'Cash','SMOKE-I-FUND',v_req_funding);
        v_retry_id:=public.post_parchi_funding(
          v_issued_id,v_doc_date,400.00,'Cash','SMOKE-I-FUND',v_req_funding);
        SELECT pg_catalog.count(*) INTO v_request_count FROM public.parchi_events
        WHERE adda_id=fixture_row.adda_id AND request_id=v_req_funding;
        SELECT pg_catalog.count(*) INTO v_cashbook_count FROM public.cashbook_entries
        WHERE reference_type='parchi_event' AND reference_id=v_issued_funding_id::text
          AND adda_id=fixture_row.adda_id AND entry_type='Cash Out' AND amount=400.00;
        IF v_issued_funding_id=v_retry_id AND v_request_count=1 AND v_cashbook_count=1 THEN
          INSERT INTO pg_temp.parchi_smoke_results VALUES ('ISSUED_PARTIAL_FUNDING_RETRY','PASS',
            'Rs 400 disbursement is Cash Out; identical retry has one event and one Cashbook row.');
        ELSE
          INSERT INTO pg_temp.parchi_smoke_results VALUES ('ISSUED_PARTIAL_FUNDING_RETRY','FAIL',
            pg_catalog.concat('same_id=',v_issued_funding_id=v_retry_id,
              '; request_events=',v_request_count,'; matching_cashbook=',v_cashbook_count));
        END IF;
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
        v_issued_funding_id:=NULL;
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('ISSUED_PARTIAL_FUNDING_RETRY','FAIL',
          pg_catalog.concat(v_state,': ',v_message));
      END;

      IF v_issued_funding_id IS NULL THEN
        INSERT INTO pg_temp.parchi_smoke_results VALUES
          ('ISSUED_OVERFUNDING_REJECTED','SKIP','Partial funding did not complete.'),
          ('ISSUED_OVERRECOVERY_REJECTED','SKIP','Partial funding did not complete.'),
          ('ISSUED_PARTIAL_RECOVERY_STATUS','SKIP','Partial funding did not complete.');
      ELSE
      BEGIN
        PERFORM public.post_parchi_funding(
          v_issued_id,v_doc_date,601.00,'Cash','SMOKE-I-OVER',pg_catalog.gen_random_uuid());
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('ISSUED_OVERFUNDING_REJECTED','FAIL',
          'Overfunding was accepted.');
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('ISSUED_OVERFUNDING_REJECTED',
          CASE WHEN v_message='PARCHI_FUNDING_EXCEEDS_DOCUMENT_AMOUNT' THEN 'PASS' ELSE 'FAIL' END,
          pg_catalog.concat(v_state,': ',v_message));
      END;

      BEGIN
        PERFORM public.post_parchi_settlement(
          v_issued_id,v_doc_date,401.00,'Cash','SMOKE-I-OVER-RECOVERY',pg_catalog.gen_random_uuid());
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('ISSUED_OVERRECOVERY_REJECTED','FAIL',
          'Recovery above funded amount was accepted.');
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('ISSUED_OVERRECOVERY_REJECTED',
          CASE WHEN v_message='PARCHI_SETTLEMENT_EXCEEDS_FUNDED_OUTSTANDING_AS_OF_DATE' THEN 'PASS' ELSE 'FAIL' END,
          pg_catalog.concat(v_state,': ',v_message));
      END;

      BEGIN
        v_req_settlement:=pg_catalog.gen_random_uuid();
        v_issued_settlement_id:=public.post_parchi_settlement(
          v_issued_id,v_doc_date,150.00,'Cash','SMOKE-I-RECOVER',v_req_settlement);
        v_retry_id:=public.post_parchi_settlement(
          v_issued_id,v_doc_date,150.00,'Cash','SMOKE-I-RECOVER',v_req_settlement);
        SELECT pg_catalog.count(*) INTO v_request_count FROM public.parchi_events
        WHERE adda_id=fixture_row.adda_id AND request_id=v_req_settlement;
        SELECT net_funded,net_settled,funded_outstanding,funding_status,settlement_status
          INTO v_net_funded,v_net_settled,v_balance,v_funding_status,v_settlement_status
        FROM public.get_parchi_statement(fixture_row.adda_id,'other_adda',fixture_row.other_adda_id)
        WHERE parchi_id=v_issued_id LIMIT 1;
        SELECT pg_catalog.count(*) INTO v_cashbook_count FROM public.cashbook_entries
        WHERE reference_type='parchi_event' AND reference_id=v_issued_settlement_id::text
          AND adda_id=fixture_row.adda_id AND entry_type='Cash In' AND amount=150.00;
        IF v_issued_settlement_id=v_retry_id AND v_request_count=1 AND v_cashbook_count=1
           AND v_net_funded=400.00 AND v_net_settled=150.00 AND v_balance=250.00
           AND v_funding_status='Partially Funded' AND v_settlement_status='Partially Settled' THEN
          INSERT INTO pg_temp.parchi_smoke_results VALUES ('ISSUED_PARTIAL_RECOVERY_STATUS','PASS',
            'Funded 400, recovered 150, outstanding 250, partially settled; recovery is Cash In; retry is idempotent.');
        ELSE
          INSERT INTO pg_temp.parchi_smoke_results VALUES ('ISSUED_PARTIAL_RECOVERY_STATUS','FAIL',
            pg_catalog.concat('funded=',v_net_funded,' settled=',v_net_settled,' outstanding=',v_balance,
              ' funding_status=',v_funding_status,' settlement_status=',v_settlement_status,
              ' retry_same=',v_issued_settlement_id=v_retry_id,' events=',v_request_count,
              ' cashbook=',v_cashbook_count));
        END IF;
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
        v_issued_settlement_id:=NULL;
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('ISSUED_PARTIAL_RECOVERY_STATUS','FAIL',
          pg_catalog.concat(v_state,': ',v_message));
      END;
      END IF;
    ELSE
      INSERT INTO pg_temp.parchi_smoke_results VALUES
        ('ISSUED_PARTIAL_FUNDING_RETRY','SKIP','Issued Parchi creation failed.'),
        ('ISSUED_OVERFUNDING_REJECTED','SKIP','Issued Parchi creation failed.'),
        ('ISSUED_OVERRECOVERY_REJECTED','SKIP','Issued Parchi creation failed.'),
        ('ISSUED_PARTIAL_RECOVERY_STATUS','SKIP','Issued Parchi creation failed.');
    END IF;
  END IF;

  -- Cross-tenant RPC attempts and direct table DML checks remain under operator JWT.
  IF fixture_row.other_tenant_adda_id IS NULL THEN
    INSERT INTO pg_temp.parchi_smoke_results VALUES ('CROSS_TENANT_DENIED','SKIP',
      'Requires at least one second Adda in the database.');
  ELSE
    BEGIN
      PERFORM public.create_parchi(
        fixture_row.other_tenant_adda_id,'received',fixture_row.broker_id,NULL,v_doc_date,100.00,
        v_funding_due,v_settlement_due,'SMOKE-CROSS','cross-tenant denial test',
        NULL,NULL,NULL,NULL,NULL,NULL,pg_catalog.gen_random_uuid());
      INSERT INTO pg_temp.parchi_smoke_results VALUES ('CROSS_TENANT_CREATE_DENIED','FAIL',
        'Operator created a Parchi under a different Adda.');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
      INSERT INTO pg_temp.parchi_smoke_results VALUES ('CROSS_TENANT_CREATE_DENIED',
        CASE WHEN v_message='PARCHI_TENANT_MISMATCH' THEN 'PASS' ELSE 'FAIL' END,
        pg_catalog.concat(v_state,': ',v_message));
    END;
    BEGIN
      PERFORM 1 FROM public.get_parchi_statement(
        fixture_row.other_tenant_adda_id,'broker',fixture_row.broker_id) LIMIT 1;
      INSERT INTO pg_temp.parchi_smoke_results VALUES ('CROSS_TENANT_STATEMENT_DENIED','FAIL',
        'Operator statement read for another Adda returned without authorization error.');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
      INSERT INTO pg_temp.parchi_smoke_results VALUES ('CROSS_TENANT_STATEMENT_DENIED',
        CASE WHEN v_message='PARCHI_TENANT_MISMATCH' THEN 'PASS' ELSE 'FAIL' END,
        pg_catalog.concat(v_state,': ',v_message));
    END;
  END IF;

  IF fixture_row.broker_id IS NOT NULL AND v_received_id IS NOT NULL THEN
    BEGIN
      PERFORM public.amend_parchi_document(v_received_id,1100.00,v_funding_due,v_settlement_due,
        'operator must not amend',pg_catalog.gen_random_uuid());
      INSERT INTO pg_temp.parchi_smoke_results VALUES ('OPERATOR_AMEND_DENIED','FAIL',
        'Operator amendment was accepted.');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
      INSERT INTO pg_temp.parchi_smoke_results VALUES ('OPERATOR_AMEND_DENIED',
        CASE WHEN v_message='PARCHI_ROLE_NOT_AUTHORIZED' THEN 'PASS' ELSE 'FAIL' END,
        pg_catalog.concat(v_state,': ',v_message));
    END;
    IF v_received_settlement_id IS NOT NULL THEN
      BEGIN
        PERFORM public.reverse_parchi_event(v_received_settlement_id,v_doc_date,
          'operator must not reverse',pg_catalog.gen_random_uuid());
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('OPERATOR_REVERSE_DENIED','FAIL',
          'Operator reversal was accepted.');
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('OPERATOR_REVERSE_DENIED',
          CASE WHEN v_message='PARCHI_ROLE_NOT_AUTHORIZED' THEN 'PASS' ELSE 'FAIL' END,
          pg_catalog.concat(v_state,': ',v_message));
      END;
    ELSE
      INSERT INTO pg_temp.parchi_smoke_results VALUES ('OPERATOR_REVERSE_DENIED','SKIP',
        'No received settlement event exists.');
    END IF;
  ELSE
    INSERT INTO pg_temp.parchi_smoke_results VALUES
      ('OPERATOR_AMEND_DENIED','SKIP','Requires a successfully created Received Parchi.'),
      ('OPERATOR_REVERSE_DENIED','SKIP','Requires a successfully created Received Parchi and settlement event.');
  END IF;

  IF NOT pg_catalog.has_table_privilege('authenticated','public.parchis','INSERT')
     AND NOT pg_catalog.has_table_privilege('authenticated','public.parchis','UPDATE')
     AND NOT pg_catalog.has_table_privilege('authenticated','public.parchis','DELETE')
     AND NOT pg_catalog.has_table_privilege('authenticated','public.parchi_events','INSERT')
     AND NOT pg_catalog.has_table_privilege('authenticated','public.parchi_events','UPDATE')
     AND NOT pg_catalog.has_table_privilege('authenticated','public.parchi_events','DELETE') THEN
    INSERT INTO pg_temp.parchi_smoke_results VALUES ('DIRECT_PARCHI_DML_DENIED','PASS',
      'Authenticated has no direct INSERT/UPDATE/DELETE privilege on either Parchi table.');
  ELSE
    INSERT INTO pg_temp.parchi_smoke_results VALUES ('DIRECT_PARCHI_DML_DENIED','FAIL',
      'Authenticated has at least one direct Parchi table write privilege.');
  END IF;

  -- Keep an unfunded document for the admin-only cancellation and cancelled-state checks.
  IF fixture_row.broker_id IS NOT NULL THEN
    BEGIN
      v_cancel_id:=public.create_parchi(
        fixture_row.adda_id,'received',fixture_row.broker_id,NULL,v_doc_date,500.00,
        v_funding_due,v_settlement_due,'SMOKE-CANCEL','unfunded cancellation test',
        NULL,NULL,NULL,NULL,NULL,NULL,pg_catalog.gen_random_uuid());
      INSERT INTO pg_temp.parchi_smoke_results VALUES ('CANCEL_FIXTURE_CREATED','PASS',v_cancel_id::text);
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
      v_cancel_id:=NULL;
      INSERT INTO pg_temp.parchi_smoke_results VALUES ('CANCEL_FIXTURE_CREATED','FAIL',
        pg_catalog.concat(v_state,': ',v_message));
    END;
    IF v_cancel_id IS NOT NULL THEN
      BEGIN
        PERFORM public.cancel_unfunded_parchi(v_cancel_id,'operator must not cancel',pg_catalog.gen_random_uuid());
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('OPERATOR_CANCEL_DENIED','FAIL',
          'Operator cancellation was accepted.');
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('OPERATOR_CANCEL_DENIED',
          CASE WHEN v_message='PARCHI_ROLE_NOT_AUTHORIZED' THEN 'PASS' ELSE 'FAIL' END,
          pg_catalog.concat(v_state,': ',v_message));
      END;
    ELSE
      INSERT INTO pg_temp.parchi_smoke_results VALUES ('OPERATOR_CANCEL_DENIED','SKIP',
        'Unfunded cancellation fixture could not be created.');
    END IF;
  ELSE
    INSERT INTO pg_temp.parchi_smoke_results VALUES
      ('CANCEL_FIXTURE_CREATED','SKIP','Requires an existing same-Adda Broker.'),
      ('OPERATOR_CANCEL_DENIED','SKIP','Requires an existing same-Adda Broker.');
  END IF;

  -- Admin-only actions use a real active Adda Admin profile, if one exists.
  IF fixture_row.admin_id IS NULL THEN
    INSERT INTO pg_temp.parchi_smoke_results VALUES
      ('ADMIN_AMEND','SKIP','Requires an active Adda Admin profile in the selected Adda.'),
      ('RECEIVED_REVERSAL','SKIP','Requires an active Adda Admin profile in the selected Adda.'),
      ('ISSUED_REVERSAL','SKIP','Requires an active Adda Admin profile in the selected Adda.'),
      ('CANCEL_UNFUNDED','SKIP','Requires an active Adda Admin profile in the selected Adda.'),
      ('CANCEL_AFTER_MONEY','SKIP','Requires an active Adda Admin profile in the selected Adda.'),
      ('CANCELLED_WRITE_REJECTED','SKIP','Requires an active Adda Admin profile in the selected Adda.');
  ELSE
    PERFORM pg_catalog.set_config('request.jwt.claims',
      pg_catalog.jsonb_build_object('sub',fixture_row.admin_id::text,
        'role','authenticated','aud','authenticated')::text,true);
    PERFORM pg_catalog.set_config('request.jwt.claim.sub',fixture_row.admin_id::text,true);
    PERFORM pg_catalog.set_config('request.jwt.claim.role','authenticated',true);

    IF v_received_id IS NOT NULL THEN
      BEGIN
        PERFORM public.amend_parchi_document(v_received_id,1200.00,v_funding_due+1,v_settlement_due+1,
          'smoke test approved amendment',pg_catalog.gen_random_uuid());
        SELECT document_amount INTO v_net_funded
        FROM public.get_parchi_statement(fixture_row.adda_id,'broker',fixture_row.broker_id)
        WHERE parchi_id=v_received_id LIMIT 1;
        IF v_net_funded=1200.00 THEN
          INSERT INTO pg_temp.parchi_smoke_results VALUES ('ADMIN_AMEND','PASS',
            'Adda Admin amended amount/due dates; statement reflects the amended source fields.');
        ELSE
          INSERT INTO pg_temp.parchi_smoke_results VALUES ('ADMIN_AMEND','FAIL',
            pg_catalog.concat('statement document_amount=',v_net_funded));
        END IF;
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('ADMIN_AMEND','FAIL',
          pg_catalog.concat(v_state,': ',v_message));
      END;
    ELSE
      INSERT INTO pg_temp.parchi_smoke_results VALUES ('ADMIN_AMEND','SKIP',
        'No Received Parchi was created.');
    END IF;

    IF v_received_settlement_id IS NOT NULL THEN
      BEGIN
        v_req_reverse:=pg_catalog.gen_random_uuid();
        v_received_reversal_id:=public.reverse_parchi_event(v_received_settlement_id,v_doc_date,
          'smoke test reversal',v_req_reverse);
        v_retry_id:=public.reverse_parchi_event(v_received_settlement_id,v_doc_date,
          'smoke test reversal',v_req_reverse);
        SELECT pg_catalog.count(*) INTO v_cashbook_count FROM public.cashbook_entries
        WHERE reference_type='parchi_event' AND reference_id=v_received_reversal_id::text
          AND adda_id=fixture_row.adda_id AND entry_type='Cash In' AND amount=150.00;
        SELECT net_settled,funded_outstanding,settlement_status
          INTO v_net_settled,v_balance,v_settlement_status
        FROM public.get_parchi_statement(fixture_row.adda_id,'broker',fixture_row.broker_id)
        WHERE parchi_id=v_received_id LIMIT 1;
        IF v_received_reversal_id=v_retry_id AND v_cashbook_count=1 AND v_net_settled=0
           AND v_balance=400.00 AND v_settlement_status='Unpaid' THEN
          INSERT INTO pg_temp.parchi_smoke_results VALUES ('RECEIVED_REVERSAL','PASS',
            'Settlement reversal is Cash In; retry produced no duplicate; net settlement returned to zero.');
        ELSE
          INSERT INTO pg_temp.parchi_smoke_results VALUES ('RECEIVED_REVERSAL','FAIL',
            pg_catalog.concat('same_id=',v_received_reversal_id=v_retry_id,' cashbook=',v_cashbook_count,
              ' net_settled=',v_net_settled,' outstanding=',v_balance,' status=',v_settlement_status));
        END IF;
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('RECEIVED_REVERSAL','FAIL',
          pg_catalog.concat(v_state,': ',v_message));
      END;
      BEGIN
        PERFORM public.cancel_unfunded_parchi(v_received_id,'money history exists',pg_catalog.gen_random_uuid());
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('CANCEL_AFTER_MONEY','FAIL',
          'A Parchi with funding/settlement/reversal history was cancelled.');
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('CANCEL_AFTER_MONEY',
          CASE WHEN v_message='PARCHI_CANCELLATION_REQUIRES_NEVER_FUNDED_DOCUMENT' THEN 'PASS' ELSE 'FAIL' END,
          pg_catalog.concat(v_state,': ',v_message));
      END;
    ELSE
      INSERT INTO pg_temp.parchi_smoke_results VALUES
        ('RECEIVED_REVERSAL','SKIP','No Received settlement event exists.'),
        ('CANCEL_AFTER_MONEY','SKIP','No Received money event exists.');
    END IF;

    IF v_issued_settlement_id IS NOT NULL THEN
      BEGIN
        v_req_reverse:=pg_catalog.gen_random_uuid();
        v_issued_reversal_id:=public.reverse_parchi_event(v_issued_settlement_id,v_doc_date,
          'smoke test reversal',v_req_reverse);
        v_retry_id:=public.reverse_parchi_event(v_issued_settlement_id,v_doc_date,
          'smoke test reversal',v_req_reverse);
        SELECT pg_catalog.count(*) INTO v_cashbook_count FROM public.cashbook_entries
        WHERE reference_type='parchi_event' AND reference_id=v_issued_reversal_id::text
          AND adda_id=fixture_row.adda_id AND entry_type='Cash Out' AND amount=150.00;
        SELECT net_settled,funded_outstanding,settlement_status
          INTO v_net_settled,v_balance,v_settlement_status
        FROM public.get_parchi_statement(fixture_row.adda_id,'other_adda',fixture_row.other_adda_id)
        WHERE parchi_id=v_issued_id LIMIT 1;
        IF v_issued_reversal_id=v_retry_id AND v_cashbook_count=1 AND v_net_settled=0
           AND v_balance=400.00 AND v_settlement_status='Unpaid' THEN
          INSERT INTO pg_temp.parchi_smoke_results VALUES ('ISSUED_REVERSAL','PASS',
            'Recovery reversal is Cash Out; retry produced no duplicate; net settlement returned to zero.');
        ELSE
          INSERT INTO pg_temp.parchi_smoke_results VALUES ('ISSUED_REVERSAL','FAIL',
            pg_catalog.concat('same_id=',v_issued_reversal_id=v_retry_id,' cashbook=',v_cashbook_count,
              ' net_settled=',v_net_settled,' outstanding=',v_balance,' status=',v_settlement_status));
        END IF;
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('ISSUED_REVERSAL','FAIL',
          pg_catalog.concat(v_state,': ',v_message));
      END;
    ELSE
      INSERT INTO pg_temp.parchi_smoke_results VALUES ('ISSUED_REVERSAL','SKIP',
        'No Issued settlement event exists.');
    END IF;

    IF v_cancel_id IS NOT NULL THEN
      BEGIN
        PERFORM public.cancel_unfunded_parchi(v_cancel_id,'smoke test cancellation',pg_catalog.gen_random_uuid());
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('CANCEL_UNFUNDED','PASS',
          'Adda Admin cancelled an unfunded document.');
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('CANCEL_UNFUNDED','FAIL',
          pg_catalog.concat(v_state,': ',v_message));
      END;
    ELSE
      INSERT INTO pg_temp.parchi_smoke_results VALUES ('CANCEL_UNFUNDED','SKIP',
        'No unfunded cancellation document exists.');
    END IF;

    -- Return to the operator profile for the post-cancellation write denial.
    PERFORM pg_catalog.set_config('request.jwt.claims',
      pg_catalog.jsonb_build_object('sub',fixture_row.operator_id::text,
        'role','authenticated','aud','authenticated')::text,true);
    PERFORM pg_catalog.set_config('request.jwt.claim.sub',fixture_row.operator_id::text,true);
    PERFORM pg_catalog.set_config('request.jwt.claim.role','authenticated',true);
    IF v_cancel_id IS NOT NULL THEN
      BEGIN
        PERFORM public.post_parchi_funding(v_cancel_id,v_doc_date,1.00,'Cash',NULL,pg_catalog.gen_random_uuid());
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('CANCELLED_WRITE_REJECTED','FAIL',
          'Funding was accepted after cancellation.');
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('CANCELLED_WRITE_REJECTED',
          CASE WHEN v_message='PARCHI_CANCELLED_DOCUMENT_REJECTS_MUTATION' THEN 'PASS' ELSE 'FAIL' END,
          pg_catalog.concat(v_state,': ',v_message));
      END;
    ELSE
      INSERT INTO pg_temp.parchi_smoke_results VALUES ('CANCELLED_WRITE_REJECTED','SKIP',
        'No cancelled document exists.');
    END IF;
  END IF;

  -- Cashbook ownership checks use a visible Parchi funding row, if the Received
  -- flow was available. A zero-row update is SKIP, never a false PASS.
  IF v_received_funding_id IS NULL THEN
    INSERT INTO pg_temp.parchi_smoke_results VALUES
      ('CASHBOOK_EDIT_DENIED','SKIP','No visible Received funding Cashbook row.'),
      ('CASHBOOK_RELABEL_DENIED','SKIP','No visible Received funding Cashbook row.'),
      ('CASHBOOK_DELETE_DENIED','SKIP','No visible Received funding Cashbook row.');
  ELSE
    BEGIN
      UPDATE public.cashbook_entries SET amount=amount+1
      WHERE reference_type='parchi_event' AND reference_id=v_received_funding_id::text;
      GET DIAGNOSTICS v_row_count=ROW_COUNT;
      IF v_row_count=0 THEN
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('CASHBOOK_EDIT_DENIED','SKIP',
          'Funding Cashbook row is not visible to authenticated role.');
      ELSE
        RAISE EXCEPTION 'PARCHI_SMOKE_MUTATION_SUCCEEDED';
      END IF;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
      INSERT INTO pg_temp.parchi_smoke_results VALUES ('CASHBOOK_EDIT_DENIED',
        CASE WHEN v_message='PARCHI_SMOKE_MUTATION_SUCCEEDED' THEN 'FAIL'
             WHEN v_state='42501' OR v_message='PARCHI_CASHBOOK_CANNOT_BE_UPDATED_OR_RELABELED' THEN 'PASS'
             ELSE 'FAIL' END,pg_catalog.concat(v_state,': ',v_message));
    END;
    BEGIN
      UPDATE public.cashbook_entries SET reference_type='manual'
      WHERE reference_type='parchi_event' AND reference_id=v_received_funding_id::text;
      GET DIAGNOSTICS v_row_count=ROW_COUNT;
      IF v_row_count=0 THEN
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('CASHBOOK_RELABEL_DENIED','SKIP',
          'Funding Cashbook row is not visible to authenticated role.');
      ELSE
        RAISE EXCEPTION 'PARCHI_SMOKE_MUTATION_SUCCEEDED';
      END IF;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
      INSERT INTO pg_temp.parchi_smoke_results VALUES ('CASHBOOK_RELABEL_DENIED',
        CASE WHEN v_message='PARCHI_SMOKE_MUTATION_SUCCEEDED' THEN 'FAIL'
             WHEN v_state='42501' OR v_message='PARCHI_CASHBOOK_CANNOT_BE_UPDATED_OR_RELABELED' THEN 'PASS'
             ELSE 'FAIL' END,pg_catalog.concat(v_state,': ',v_message));
    END;
    BEGIN
      DELETE FROM public.cashbook_entries
      WHERE reference_type='parchi_event' AND reference_id=v_received_funding_id::text;
      GET DIAGNOSTICS v_row_count=ROW_COUNT;
      IF v_row_count=0 THEN
        INSERT INTO pg_temp.parchi_smoke_results VALUES ('CASHBOOK_DELETE_DENIED','SKIP',
          'Funding Cashbook row is not visible to authenticated role.');
      ELSE
        RAISE EXCEPTION 'PARCHI_SMOKE_MUTATION_SUCCEEDED';
      END IF;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
      INSERT INTO pg_temp.parchi_smoke_results VALUES ('CASHBOOK_DELETE_DENIED',
        CASE WHEN v_message='PARCHI_SMOKE_MUTATION_SUCCEEDED' THEN 'FAIL'
             WHEN v_state='42501' OR v_message='PARCHI_CASHBOOK_IS_APPEND_ONLY' THEN 'PASS'
             ELSE 'FAIL' END,pg_catalog.concat(v_state,': ',v_message));
    END;
  END IF;

  v_fake_event_id:=pg_catalog.gen_random_uuid();
  PERFORM pg_catalog.set_config('ut.parchi_cashbook_event_id',v_fake_event_id::text,true);
  BEGIN
    INSERT INTO public.cashbook_entries(
      entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,
      payment_method,amount,description,reference_type,reference_id,adda_id
    ) VALUES (
      v_doc_date,'Cash In','Broker','Parchi smoke test',NULL,NULL,NULL,'Cash',1.00,
      'forged test row','parchi_event',v_fake_event_id::text,fixture_row.adda_id
    );
    INSERT INTO pg_temp.parchi_smoke_results VALUES ('CASHBOOK_FORGED_SOURCE_DENIED','FAIL',
      'Client-set event GUC and fabricated event ID were accepted.');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT;
    INSERT INTO pg_temp.parchi_smoke_results VALUES ('CASHBOOK_FORGED_SOURCE_DENIED',
      CASE WHEN v_state='42501' OR v_message='PARCHI_CASHBOOK_POSTING_RPC_REQUIRED'
        OR v_message='PARCHI_CASHBOOK_SOURCE_EVENT_MISSING' THEN 'PASS' ELSE 'FAIL' END,
      pg_catalog.concat(v_state,': ',v_message));
  END;
END;
$parchi_smoke$;

RESET ROLE;

-- Results are emitted before rollback. Any unexpected success is FAIL; missing
-- fixture-dependent coverage is explicitly SKIP with the needed fixture.
SELECT test_name,result,details
FROM pg_temp.parchi_smoke_results
UNION ALL
SELECT 'OVERALL',
       CASE WHEN pg_catalog.count(*) FILTER (WHERE result='FAIL')>0 THEN 'FAIL'
            WHEN pg_catalog.count(*) FILTER (WHERE result='SKIP')>0 THEN 'SKIP'
            ELSE 'PASS' END,
       pg_catalog.concat('pass=',pg_catalog.count(*) FILTER (WHERE result='PASS'),
         '; fail=',pg_catalog.count(*) FILTER (WHERE result='FAIL'),
         '; skip=',pg_catalog.count(*) FILTER (WHERE result='SKIP'))
FROM pg_temp.parchi_smoke_results
ORDER BY test_name;

ROLLBACK;
