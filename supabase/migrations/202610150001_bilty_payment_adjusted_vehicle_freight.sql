BEGIN;

DO $bilty_payment_adjusted_freight$
DECLARE
  payment_oid oid := pg_catalog.to_regprocedure(
    'public.add_bilty_payment(uuid,text,date,numeric,text,text,text)'
  );
  summary_oid oid := pg_catalog.to_regprocedure(
    'public.get_bilty_financial_summary(uuid)'
  );
  payment_source text;
  summary_source text;
  payment_definition text;
  summary_definition text;
  function_delimiter text;
  definition_match text[];
  cap_match text[];
  guard_pattern constant text :=
    'IF[[:space:]]+[^;]*p_payment_side[[:space:]]*=[[:space:]]*''party_broker''[^;]*bilty_party_id[[:space:]]+IS[[:space:]]+NULL[^;]*bilty_broker_id[[:space:]]+IS[[:space:]]+NULL[^;]*THEN[[:space:]]+RAISE([[:space:]]+EXCEPTION)?[^;]*This Bilty has no Party or Broker account[^;]*;[[:space:]]*END[[:space:]]+IF[[:space:]]*;?';
  party_cap_pattern constant text :=
    '\mIF\M[^;]*p_payment_side[^;]*''party_broker''[^;]*(\mp_amount\M[^;]*\mfreight\M|\mfreight\M[^;]*\mp_amount\M)[^;]*>[^;]*\mTHEN\M[[:space:]]*RAISE';
  guard_count integer;
  cap_count integer := 0;
  cap_clause text;
  replacement_cap_clause text;
  declaration_position integer;
  open_position integer;
  close_position integer;
  close_relative_position integer;
  rewritten_definition text;
  calc_prefix constant text := $calc$
  adjusted_vehicle_freight_amount := (
    SELECT coalesce(booking.vehicle_freight, 0)
         - coalesce(booking.broker_commission, 0)
         + coalesce(booking.overweight_charges, 0)
         + coalesce(booking.lolo_charges, 0)
         + coalesce(booking.detain_charges, 0)
    FROM public.bookings AS booking
    WHERE booking.id = p_bilty_id
    FOR UPDATE
  );
  IF adjusted_vehicle_freight_amount IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'BILTY_NOT_FOUND';
  END IF;
$calc$;
  original_payment_owner oid;
  original_payment_acl text;
  original_payment_result text;
  original_payment_security boolean;
  original_payment_volatility "char";
  original_payment_config text[];
  original_payment_arguments oidvector;
  original_payment_argnames text[];
  original_payment_argmodes "char"[];
  original_summary_owner oid;
  original_summary_acl text;
  original_summary_result text;
  original_summary_security boolean;
  original_summary_volatility "char";
  original_summary_config text[];
  original_summary_arguments oidvector;
  original_summary_argnames text[];
  original_summary_argmodes "char"[];
  output_names text[];
  output_items text[] := ARRAY[]::text[];
  original_output_items text[] := ARRAY[]::text[];
  total_vehicle_paid_expression text;
  output_index integer;
  vehicle_balance_index integer;
  total_vehicle_paid_index integer;
  vehicle_freight_index integer;
  adda_commission_index integer;
  source_length integer;
  scan_position integer;
  scan_start integer;
  projection_start integer;
  select_end integer;
  item_start integer;
  paren_depth integer := 0;
  lexical_state text := 'normal';
  dollar_delimiter text;
  block_depth integer := 0;
  current_character text;
  next_character text;
  preceding_character text;
  following_character text;
  lower_source text;
  select_found boolean := false;
BEGIN
  IF payment_oid IS NULL OR summary_oid IS NULL THEN
    RAISE EXCEPTION 'BILTY_PAYMENT_ADJUSTED_FREIGHT: expected deployed RPC signature is missing';
  END IF;

  IF (SELECT count(*) FROM pg_catalog.pg_proc AS procedure_row
      JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=procedure_row.pronamespace
      WHERE namespace_row.nspname='public' AND procedure_row.proname='add_bilty_payment') <> 1
     OR (SELECT count(*) FROM pg_catalog.pg_proc AS procedure_row
         JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=procedure_row.pronamespace
         WHERE namespace_row.nspname='public' AND procedure_row.proname='get_bilty_financial_summary') <> 1 THEN
    RAISE EXCEPTION 'BILTY_PAYMENT_ADJUSTED_FREIGHT: unexpected overload or duplicate RPC';
  END IF;

  IF pg_catalog.to_regclass('public.bilty_payments') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_attribute AS attribute_row
       WHERE attribute_row.attrelid='public.bookings'::pg_catalog.regclass
         AND attribute_row.attname IN ('vehicle_freight','broker_commission','overweight_charges','lolo_charges','detain_charges')
         AND attribute_row.atttypid='numeric'::pg_catalog.regtype
         AND attribute_row.attnum>0
         AND NOT attribute_row.attisdropped
       GROUP BY attribute_row.attrelid
       HAVING count(DISTINCT attribute_row.attname)=5
     ) THEN
    RAISE EXCEPTION 'BILTY_PAYMENT_ADJUSTED_FREIGHT: payment table or adjusted freight input columns are missing';
  END IF;

  SELECT procedure_row.prosrc, procedure_row.proowner, procedure_row.proacl::text,
         pg_catalog.pg_get_function_result(procedure_row.oid), procedure_row.prosecdef,
         procedure_row.provolatile, procedure_row.proconfig, procedure_row.proargtypes,
         procedure_row.proargnames, procedure_row.proargmodes
  INTO payment_source, original_payment_owner, original_payment_acl,
       original_payment_result, original_payment_security, original_payment_volatility,
       original_payment_config, original_payment_arguments,
       original_payment_argnames, original_payment_argmodes
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid=payment_oid;

  SELECT count(*) INTO guard_count
  FROM pg_catalog.regexp_matches(payment_source, guard_pattern, 'gi');
  IF guard_count <> 1 THEN
    RAISE EXCEPTION 'BILTY_PAYMENT_ADJUSTED_FREIGHT: expected exactly one Party/Broker no-account guard; found %', guard_count;
  END IF;

  IF payment_source ~* '\madjusted_vehicle_freight_amount\M'
     OR payment_source !~* '^\s*DECLARE\M'
     OR payment_source !~* '\mp_bilty_id\M'
     OR payment_source !~* '\mvehicle_freight_amount\M' THEN
    RAISE EXCEPTION 'BILTY_PAYMENT_ADJUSTED_FREIGHT: payment writer declaration or raw-cap baseline drift';
  END IF;

  payment_source := pg_catalog.regexp_replace(payment_source, guard_pattern, '', 'gi');

  FOR cap_match IN
    SELECT pg_catalog.regexp_matches(
      payment_source,
      '(\mIF\M[[:space:]]*([^;]*?)\mTHEN\M)',
      'gis'
    )
  LOOP
    IF cap_match[2] ~* '\mvehicle_freight_amount\M'
       AND cap_match[2] ~* '\mp_amount\M'
       AND cap_match[2] ~ '[<>]' THEN
      cap_count := cap_count + 1;
      cap_clause := cap_match[1];
    END IF;
  END LOOP;

  IF cap_count <> 1 OR cap_clause IS NULL THEN
    RAISE EXCEPTION 'BILTY_PAYMENT_ADJUSTED_FREIGHT: expected exactly one vehicle amount cap using vehicle_freight_amount and p_amount; found %', cap_count;
  END IF;

  replacement_cap_clause := pg_catalog.regexp_replace(
    cap_clause,
    '\mvehicle_freight_amount\M',
    'adjusted_vehicle_freight_amount',
    'gi'
  );

  IF pg_catalog.length(payment_source)
       - pg_catalog.length(pg_catalog.replace(payment_source, cap_clause, ''))
       <> pg_catalog.length(cap_clause) THEN
    RAISE EXCEPTION 'BILTY_PAYMENT_ADJUSTED_FREIGHT: vehicle cap clause is not uniquely addressable';
  END IF;

  declaration_position := pg_catalog.strpos(pg_catalog.lower(payment_source), 'declare');
  payment_source := pg_catalog.substring(payment_source, 1, declaration_position - 1)
    || 'DECLARE' || E'\n  adjusted_vehicle_freight_amount numeric;'
    || pg_catalog.substring(payment_source, declaration_position + 7);

  payment_source := pg_catalog.replace(
    payment_source,
    cap_clause,
    calc_prefix || replacement_cap_clause
  );

  IF payment_source ~* guard_pattern
     OR payment_source ~* 'This Bilty has no Party or Broker account'
     OR pg_catalog.strpos(payment_source, calc_prefix) = 0
     OR payment_source !~* '\madjusted_vehicle_freight_amount\M' THEN
    RAISE EXCEPTION 'BILTY_PAYMENT_ADJUSTED_FREIGHT: payment source transformation did not produce the required guard/cap';
  END IF;

  payment_definition := pg_catalog.pg_get_functiondef(payment_oid);
  definition_match := pg_catalog.regexp_match(payment_definition, 'AS[[:space:]]+(\$[[:alnum:]_]*\$)', 'i');
  IF definition_match IS NULL THEN
    RAISE EXCEPTION 'BILTY_PAYMENT_ADJUSTED_FREIGHT: cannot locate payment function body delimiter';
  END IF;
  function_delimiter := definition_match[1];
  open_position := pg_catalog.strpos(payment_definition, function_delimiter);
  close_relative_position := pg_catalog.strpos(
    pg_catalog.substring(payment_definition, open_position + pg_catalog.length(function_delimiter)),
    function_delimiter
  );
  IF open_position=0 OR close_relative_position=0 THEN
    RAISE EXCEPTION 'BILTY_PAYMENT_ADJUSTED_FREIGHT: payment function body delimiter is malformed';
  END IF;
  close_position := open_position + pg_catalog.length(function_delimiter) + close_relative_position - 1;
  rewritten_definition := pg_catalog.substring(payment_definition, 1, open_position + pg_catalog.length(function_delimiter) - 1)
    || payment_source || function_delimiter
    || pg_catalog.substring(payment_definition, close_position + pg_catalog.length(function_delimiter));
  EXECUTE rewritten_definition;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid=payment_oid
      AND procedure_row.proowner=original_payment_owner
      AND procedure_row.proacl::text IS NOT DISTINCT FROM original_payment_acl
      AND pg_catalog.pg_get_function_result(procedure_row.oid) IS NOT DISTINCT FROM original_payment_result
      AND procedure_row.prosecdef=original_payment_security
      AND procedure_row.provolatile=original_payment_volatility
      AND procedure_row.proconfig IS NOT DISTINCT FROM original_payment_config
      AND procedure_row.proargtypes=original_payment_arguments
      AND procedure_row.proargnames IS NOT DISTINCT FROM original_payment_argnames
      AND procedure_row.proargmodes IS NOT DISTINCT FROM original_payment_argmodes
      AND procedure_row.prosrc !~* guard_pattern
      AND pg_catalog.strpos(pg_catalog.lower(procedure_row.prosrc), 'this bilty has no party or broker account') = 0
      AND procedure_row.prosrc ~* party_cap_pattern
      AND procedure_row.prosrc ~* '\madvance_bilty\M'
      AND procedure_row.prosrc ~* 'adjusted_vehicle_freight_amount'
      AND procedure_row.prosrc ~* 'coalesce[[:space:]]*[(]booking[.]vehicle_freight[[:space:]]*,[[:space:]]*0[)]'
      AND procedure_row.prosrc ~* 'coalesce[[:space:]]*[(]booking[.]broker_commission[[:space:]]*,[[:space:]]*0[)]'
      AND procedure_row.prosrc ~* 'coalesce[[:space:]]*[(]booking[.]overweight_charges[[:space:]]*,[[:space:]]*0[)]'
      AND procedure_row.prosrc ~* 'coalesce[[:space:]]*[(]booking[.]lolo_charges[[:space:]]*,[[:space:]]*0[)]'
      AND procedure_row.prosrc ~* 'coalesce[[:space:]]*[(]booking[.]detain_charges[[:space:]]*,[[:space:]]*0[)]'
      AND procedure_row.prosrc ~* 'coalesce[[:space:]]*[(]booking[.]vehicle_freight[[:space:]]*,[[:space:]]*0[)]\s*-\s*coalesce[[:space:]]*[(]booking[.]broker_commission[[:space:]]*,[[:space:]]*0[)]\s*\+\s*coalesce[[:space:]]*[(]booking[.]overweight_charges[[:space:]]*,[[:space:]]*0[)]\s*\+\s*coalesce[[:space:]]*[(]booking[.]lolo_charges[[:space:]]*,[[:space:]]*0[)]\s*\+\s*coalesce[[:space:]]*[(]booking[.]detain_charges[[:space:]]*,[[:space:]]*0[)]'
      AND procedure_row.prosrc ~* '\mIF\M[^;]*(\madjusted_vehicle_freight_amount\M[^;]*\mp_amount\M|\mp_amount\M[^;]*\madjusted_vehicle_freight_amount\M)[^;]*[<>][^;]*\mTHEN\M'
  ) THEN
    RAISE EXCEPTION 'BILTY_PAYMENT_ADJUSTED_FREIGHT: payment RPC postcondition failed';
  END IF;

  SELECT procedure_row.prosrc, procedure_row.proowner, procedure_row.proacl::text,
         pg_catalog.pg_get_function_result(procedure_row.oid), procedure_row.prosecdef,
         procedure_row.provolatile, procedure_row.proconfig, procedure_row.proargtypes,
         procedure_row.proargnames, procedure_row.proargmodes
  INTO summary_source, original_summary_owner, original_summary_acl,
       original_summary_result, original_summary_security, original_summary_volatility,
       original_summary_config, original_summary_arguments,
       original_summary_argnames, original_summary_argmodes
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid=summary_oid;

  SELECT pg_catalog.array_agg(procedure_row.proargnames[mode_row.ordinality::integer] ORDER BY mode_row.ordinality)
  INTO output_names
  FROM pg_catalog.pg_proc AS procedure_row
  CROSS JOIN LATERAL pg_catalog.unnest(procedure_row.proargmodes)
    WITH ORDINALITY AS mode_row(argument_mode, ordinality)
  WHERE procedure_row.oid=summary_oid
    AND mode_row.argument_mode IN ('o','b','t');

  IF output_names IS NULL
     OR NOT ('vehicle_balance'=ANY(output_names))
     OR NOT ('total_vehicle_paid'=ANY(output_names))
     OR NOT ('vehicle_freight'=ANY(output_names))
     OR NOT ('adda_commission'=ANY(output_names))
     OR original_summary_result NOT ILIKE '%vehicle_balance%' THEN
    RAISE EXCEPTION 'BILTY_PAYMENT_ADJUSTED_FREIGHT: summary return contract is not the expected table shape';
  END IF;

  vehicle_balance_index := NULL;
  total_vehicle_paid_index := NULL;
  vehicle_freight_index := NULL;
  adda_commission_index := NULL;
  FOR output_index IN 1..pg_catalog.array_length(output_names,1) LOOP
    CASE pg_catalog.lower(output_names[output_index])
      WHEN 'vehicle_balance' THEN vehicle_balance_index := output_index;
      WHEN 'total_vehicle_paid' THEN total_vehicle_paid_index := output_index;
      WHEN 'vehicle_freight' THEN vehicle_freight_index := output_index;
      WHEN 'adda_commission' THEN adda_commission_index := output_index;
    END CASE;
  END LOOP;

  source_length := pg_catalog.length(summary_source);
  lower_source := pg_catalog.lower(summary_source);
  scan_start := pg_catalog.strpos(lower_source, 'return query');
  IF scan_start > 0 THEN
    scan_start := scan_start + pg_catalog.length('return query');
  ELSE
    scan_start := 1;
  END IF;

  scan_position := scan_start;
  WHILE scan_position <= source_length LOOP
    current_character := pg_catalog.substring(summary_source, scan_position, 1);
    next_character := pg_catalog.substring(summary_source, scan_position + 1, 1);
    preceding_character := CASE WHEN scan_position > 1 THEN pg_catalog.substring(summary_source, scan_position - 1, 1) ELSE '' END;
    following_character := pg_catalog.substring(summary_source, scan_position + 1);

    IF lexical_state='single' THEN
      IF current_character='''' AND next_character='''' THEN
        scan_position := scan_position + 2;
        CONTINUE;
      ELSIF current_character='''' THEN
        lexical_state := 'normal';
      END IF;
    ELSIF lexical_state='double' THEN
      IF current_character='"' AND next_character='"' THEN
        scan_position := scan_position + 2;
        CONTINUE;
      ELSIF current_character='"' THEN
        lexical_state := 'normal';
      END IF;
    ELSIF lexical_state='line_comment' THEN
      IF current_character=E'\n' THEN lexical_state := 'normal'; END IF;
    ELSIF lexical_state='block_comment' THEN
      IF current_character='/' AND next_character='*' THEN
        block_depth := block_depth + 1;
        scan_position := scan_position + 2;
        CONTINUE;
      ELSIF current_character='*' AND next_character='/' THEN
        block_depth := block_depth - 1;
        scan_position := scan_position + 2;
        IF block_depth=0 THEN lexical_state := 'normal'; END IF;
        CONTINUE;
      END IF;
    ELSIF lexical_state='dollar_comment' THEN
      IF pg_catalog.substring(summary_source, scan_position, pg_catalog.length(dollar_delimiter))=dollar_delimiter THEN
        scan_position := scan_position + pg_catalog.length(dollar_delimiter);
        lexical_state := 'normal';
        CONTINUE;
      END IF;
    ELSE
      IF current_character='-' AND next_character='-' THEN
        lexical_state := 'line_comment';
        scan_position := scan_position + 2;
        CONTINUE;
      ELSIF current_character='/' AND next_character='*' THEN
        lexical_state := 'block_comment';
        block_depth := 1;
        scan_position := scan_position + 2;
        CONTINUE;
      ELSIF current_character='''' THEN
        lexical_state := 'single';
      ELSIF current_character='"' THEN
        lexical_state := 'double';
      ELSIF current_character='$' THEN
        definition_match := pg_catalog.regexp_match(
          pg_catalog.substring(summary_source, scan_position),
          '^\$[[:alnum:]_]*\$'
        );
        IF definition_match IS NOT NULL THEN
          dollar_delimiter := definition_match[1];
          lexical_state := 'dollar_comment';
          scan_position := scan_position + pg_catalog.length(dollar_delimiter);
          CONTINUE;
        END IF;
      ELSIF current_character='(' THEN
        paren_depth := paren_depth + 1;
      ELSIF current_character=')' THEN
        paren_depth := paren_depth - 1;
        IF paren_depth < 0 THEN
          RAISE EXCEPTION 'BILTY_PAYMENT_ADJUSTED_FREIGHT: summary projection has unbalanced parentheses';
        END IF;
      ELSIF paren_depth=0
        AND pg_catalog.lower(pg_catalog.substring(summary_source, scan_position, 6))='select'
        AND (preceding_character='' OR preceding_character !~ '[[:alnum:]_$]')
        AND (pg_catalog.substring(summary_source, scan_position + 6, 1)='' OR pg_catalog.substring(summary_source, scan_position + 6, 1) !~ '[[:alnum:]_$]') THEN
        select_found := true;
        item_start := scan_position + 6;
        projection_start := item_start;
        scan_position := scan_position + 6;
        CONTINUE;
      ELSIF select_found AND paren_depth=0
        AND pg_catalog.lower(pg_catalog.substring(summary_source, scan_position, 4))='from'
        AND (preceding_character='' OR preceding_character !~ '[[:alnum:]_$]')
        AND (following_character='' OR following_character !~ '[[:alnum:]_$]') THEN
        output_items := pg_catalog.array_append(
          output_items,
          pg_catalog.substring(summary_source, item_start, scan_position-item_start)
        );
        select_end := scan_position;
        EXIT;
      ELSIF select_found AND paren_depth=0 AND current_character=',' THEN
        output_items := pg_catalog.array_append(
          output_items,
          pg_catalog.substring(summary_source, item_start, scan_position-item_start)
        );
        item_start := scan_position + 1;
      END IF;
    END IF;
    scan_position := scan_position + 1;
  END LOOP;

  IF NOT select_found OR select_end IS NULL
     OR pg_catalog.array_length(output_items,1) IS DISTINCT FROM pg_catalog.array_length(output_names,1) THEN
    RAISE EXCEPTION 'BILTY_PAYMENT_ADJUSTED_FREIGHT: cannot safely map the summary output projection to its return signature';
  END IF;

  original_output_items := output_items;
  total_vehicle_paid_expression := pg_catalog.btrim(pg_catalog.regexp_replace(
    output_items[total_vehicle_paid_index],
    '[[:space:]]+AS[[:space:]]+"?total_vehicle_paid"?[[:space:]]*$',
    '',
    'i'
  ));
  IF total_vehicle_paid_expression=pg_catalog.btrim(output_items[total_vehicle_paid_index]) THEN
    total_vehicle_paid_expression := pg_catalog.btrim(pg_catalog.regexp_replace(
      output_items[total_vehicle_paid_index],
      '[[:space:]]+"?total_vehicle_paid"?[[:space:]]*$',
      '',
      'i'
    ));
  END IF;
  IF total_vehicle_paid_expression IS NULL OR total_vehicle_paid_expression='' THEN
    RAISE EXCEPTION 'BILTY_PAYMENT_ADJUSTED_FREIGHT: cannot safely reuse total_vehicle_paid projection';
  END IF;

  IF original_output_items[vehicle_freight_index] !~* '\mvehicle_freight\M'
     OR original_output_items[vehicle_freight_index] ~* '(broker_commission|overweight_charges|lolo_charges|detain_charges)'
     OR original_output_items[adda_commission_index] !~* '\mfreight\M[^;]*-[^;]*\mvehicle_freight\M'
     OR original_output_items[adda_commission_index] ~* '(broker_commission|overweight_charges|lolo_charges|detain_charges)' THEN
    RAISE EXCEPTION 'BILTY_PAYMENT_ADJUSTED_FREIGHT: summary raw vehicle freight or raw Adda Commission projection baseline is incompatible';
  END IF;

  output_items[vehicle_balance_index] :=
    'GREATEST((SELECT coalesce(booking.vehicle_freight, 0)'
    || ' - coalesce(booking.broker_commission, 0)'
    || ' + coalesce(booking.overweight_charges, 0)'
    || ' + coalesce(booking.lolo_charges, 0)'
    || ' + coalesce(booking.detain_charges, 0)'
    || ' FROM public.bookings AS booking WHERE booking.id = p_bilty_id)'
    || ' - (' || total_vehicle_paid_expression || '), 0::numeric) AS vehicle_balance';

  IF output_items[vehicle_freight_index] IS DISTINCT FROM original_output_items[vehicle_freight_index]
     OR output_items[adda_commission_index] IS DISTINCT FROM original_output_items[adda_commission_index] THEN
    RAISE EXCEPTION 'BILTY_PAYMENT_ADJUSTED_FREIGHT: raw vehicle freight or Adda Commission projection changed';
  END IF;

  summary_source := pg_catalog.substring(summary_source, 1, projection_start - 1)
    || pg_catalog.array_to_string(output_items, ',')
    || pg_catalog.substring(summary_source, select_end);

  IF summary_source !~* 'coalesce[[:space:]]*[(]booking[.]vehicle_freight[[:space:]]*,[[:space:]]*0[)]'
     OR summary_source !~* 'coalesce[[:space:]]*[(]booking[.]broker_commission[[:space:]]*,[[:space:]]*0[)]'
     OR summary_source !~* 'coalesce[[:space:]]*[(]booking[.]overweight_charges[[:space:]]*,[[:space:]]*0[)]'
     OR summary_source !~* 'coalesce[[:space:]]*[(]booking[.]lolo_charges[[:space:]]*,[[:space:]]*0[)]'
     OR summary_source !~* 'coalesce[[:space:]]*[(]booking[.]detain_charges[[:space:]]*,[[:space:]]*0[)]'
     OR summary_source !~* '\mvehicle_balance\M'
     OR pg_catalog.strpos(summary_source, original_output_items[vehicle_freight_index]) = 0
     OR pg_catalog.strpos(summary_source, original_output_items[adda_commission_index]) = 0 THEN
    RAISE EXCEPTION 'BILTY_PAYMENT_ADJUSTED_FREIGHT: summary source transformation is invalid';
  END IF;

  summary_definition := pg_catalog.pg_get_functiondef(summary_oid);
  definition_match := pg_catalog.regexp_match(summary_definition, 'AS[[:space:]]+(\$[[:alnum:]_]*\$)', 'i');
  IF definition_match IS NULL THEN
    RAISE EXCEPTION 'BILTY_PAYMENT_ADJUSTED_FREIGHT: cannot locate summary function body delimiter';
  END IF;
  function_delimiter := definition_match[1];
  open_position := pg_catalog.strpos(summary_definition, function_delimiter);
  close_relative_position := pg_catalog.strpos(
    pg_catalog.substring(summary_definition, open_position + pg_catalog.length(function_delimiter)),
    function_delimiter
  );
  IF open_position=0 OR close_relative_position=0 THEN
    RAISE EXCEPTION 'BILTY_PAYMENT_ADJUSTED_FREIGHT: summary function body delimiter is malformed';
  END IF;
  close_position := open_position + pg_catalog.length(function_delimiter) + close_relative_position - 1;
  rewritten_definition := pg_catalog.substring(summary_definition, 1, open_position + pg_catalog.length(function_delimiter) - 1)
    || summary_source || function_delimiter
    || pg_catalog.substring(summary_definition, close_position + pg_catalog.length(function_delimiter));
  EXECUTE rewritten_definition;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid=summary_oid
      AND procedure_row.proowner=original_summary_owner
      AND procedure_row.proacl::text IS NOT DISTINCT FROM original_summary_acl
      AND pg_catalog.pg_get_function_result(procedure_row.oid) IS NOT DISTINCT FROM original_summary_result
      AND procedure_row.prosecdef=original_summary_security
      AND procedure_row.provolatile=original_summary_volatility
      AND procedure_row.proconfig IS NOT DISTINCT FROM original_summary_config
      AND procedure_row.proargtypes=original_summary_arguments
      AND procedure_row.proargnames IS NOT DISTINCT FROM original_summary_argnames
      AND procedure_row.proargmodes IS NOT DISTINCT FROM original_summary_argmodes
      AND pg_catalog.lower(pg_catalog.regexp_replace(procedure_row.prosrc, '[[:space:]]+', ' ', 'g'))
          IS NOT DISTINCT FROM
          pg_catalog.lower(pg_catalog.regexp_replace(summary_source, '[[:space:]]+', ' ', 'g'))
      AND procedure_row.prosrc ~* '\mvehicle_balance\M'
      AND procedure_row.prosrc ~* '\mfreight\M[^;]*-[^;]*\mvehicle_freight\M'
      AND procedure_row.prosrc ~* 'coalesce[[:space:]]*[(]booking[.]detain_charges[[:space:]]*,[[:space:]]*0[)]'
      AND procedure_row.prosrc ~* 'coalesce[[:space:]]*[(]booking[.]broker_commission[[:space:]]*,[[:space:]]*0[)]'
      AND procedure_row.prosrc ~* 'coalesce[[:space:]]*[(]booking[.]overweight_charges[[:space:]]*,[[:space:]]*0[)]'
      AND procedure_row.prosrc ~* 'coalesce[[:space:]]*[(]booking[.]lolo_charges[[:space:]]*,[[:space:]]*0[)]'
      AND procedure_row.prosrc ~* 'coalesce[[:space:]]*[(]booking[.]vehicle_freight[[:space:]]*,[[:space:]]*0[)]'
  ) THEN
    RAISE EXCEPTION 'BILTY_PAYMENT_ADJUSTED_FREIGHT: summary RPC postcondition failed';
  END IF;
END;
$bilty_payment_adjusted_freight$;

COMMIT;
