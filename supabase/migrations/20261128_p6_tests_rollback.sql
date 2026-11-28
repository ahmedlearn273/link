BEGIN;
DO $test$
DECLARE v_cust uuid; v_owner uuid; v_r jsonb; v_a text; rec record; v_t text;
BEGIN
  SELECT customer_id INTO v_cust FROM public.service_requests LIMIT 1;
  SELECT p.id INTO v_owner FROM public.profiles p WHERE p.id::text LIKE '2213f856%';
  IF v_cust IS NULL OR v_owner IS NULL THEN RAISE EXCEPTION 'fixtures missing'; END IF;
  IF (SELECT count(*) FROM private.prime_occasions) < 50 THEN RAISE EXCEPTION 'occasions not loaded'; END IF;

  -- direct personality function: every small-talk intent answers, unknown intent returns NULL
  FOR rec IN SELECT unnest(ARRAY['greeting','thanks','bye','who_are_you','robot_q','creator','joke','compliment','mild_insult','sorry','bored','hungry','weather','congrats','love','time_ask','date_ask','occasion_greet']) AS i LOOP
    v_a := private.prime_personality(rec.i, 'سلام', 'أحمد', 'customer');
    IF v_a IS NULL OR length(v_a) < 5 THEN RAISE EXCEPTION 'intent % returned nothing', rec.i; END IF;
    IF v_a ~ 'فني' THEN RAISE EXCEPTION 'forbidden term in %', rec.i; END IF;
  END LOOP;
  IF private.prime_personality('price', 'x', 'x', 'customer') IS NOT NULL THEN RAISE EXCEPTION 'non-smalltalk must be NULL'; END IF;

  -- greeting sub-types
  IF private.prime_personality('greeting', 'سلام عليكم', NULL, 'customer') !~ 'السلام' THEN RAISE EXCEPTION 'salam reply wrong'; END IF;
  IF private.prime_personality('greeting', 'ازيك', 'منى', 'customer') !~ 'منى' THEN RAISE EXCEPTION 'name missing'; END IF;
  IF private.prime_personality('greeting', 'سلام', 'أحمد', 'owner') !~ 'باشا' THEN RAISE EXCEPTION 'owner address missing'; END IF;
  IF private.prime_personality('greeting', 'سلام', 'منى', 'customer') ~ 'باشا' THEN RAISE EXCEPTION 'باشا for non-admin'; END IF;

  -- date answer has today's Cairo date
  v_t := to_char(now() AT TIME ZONE 'Africa/Cairo', 'DD/MM/YYYY');
  IF private.prime_personality('date_ask', 'x', NULL, 'customer') NOT LIKE '%' || v_t || '%' THEN RAISE EXCEPTION 'date_ask wrong'; END IF;

  -- a test occasion covering today shows in the greeting
  INSERT INTO private.prime_occasions (code, name_ar, starts_on, ends_on, greeting, is_estimate)
    VALUES ('test_occ', 'اختبار', (now() AT TIME ZONE 'Africa/Cairo')::date, (now() AT TIME ZONE 'Africa/Cairo')::date, 'كل سنة وانت طيب بمناسبة الاختبار', false);
  IF private.prime_personality('greeting', 'سلام', NULL, 'customer') NOT LIKE '%بمناسبة الاختبار%' THEN RAISE EXCEPTION 'occasion not in greeting'; END IF;

  -- occasion_when
  v_a := private.prime_personality('occasion_when', 'امتى رمضان', NULL, 'customer');
  IF v_a IS NULL OR v_a !~ '(باقي|احنا)' THEN RAISE EXCEPTION 'occasion_when wrong: %', v_a; END IF;

  -- end to end through prime_answer, as customer and owner
  PERFORM set_config('request.jwt.claim.sub', v_cust::text, true);
  FOR rec IN SELECT * FROM (VALUES ('اهلا'),('صباح الخير'),('ازيك'),('شكرا'),('مين انت'),('قولي نكتة'),('الساعة كام'),('النهارده كام'),('امتى رمضان'),('كل سنة وانت طيب')) t(q) LOOP
    v_r := public.prime_answer(rec.q);
    IF coalesce(v_r->>'answer','') = '' THEN RAISE EXCEPTION 'prime_answer empty for %', rec.q; END IF;
  END LOOP;
  -- service questions still route to services
  v_r := public.prime_answer('عايز سباك في سموحة');
  IF v_r->>'answer' !~ 'سباك' THEN RAISE EXCEPTION 'service routing broke: %', v_r->>'answer'; END IF;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  v_r := public.prime_answer('اهلا');
  IF v_r->>'answer' !~ 'باشا' THEN RAISE EXCEPTION 'owner greeting lacks address'; END IF;
  RAISE NOTICE 'P6 tests passed';
END
$test$;
ROLLBACK;
