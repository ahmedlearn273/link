BEGIN;
DO $test$
DECLARE v_staff uuid; v_sugg jsonb; v_cust uuid; v_prov uuid; v_owner uuid; v_r jsonb; v_a text; v_ok boolean; v_n bigint; v_svc text;
BEGIN
  SELECT customer_id INTO v_cust FROM public.service_requests LIMIT 1;
  SELECT pp.user_id INTO v_prov FROM public.provider_profiles pp JOIN public.profiles p ON p.id=pp.user_id WHERE p.status='active' LIMIT 1;
  SELECT id INTO v_owner FROM public.profiles WHERE id='2213f856-0000-0000-0000-000000000000'::uuid OR false;
  SELECT p.id INTO v_owner FROM public.profiles p WHERE p.id::text LIKE '2213f856%';
  IF v_cust IS NULL OR v_prov IS NULL OR v_owner IS NULL THEN RAISE EXCEPTION 'fixtures missing'; END IF;

  -- no auth refused
  PERFORM set_config('request.jwt.claim.sub','',true);
  v_ok:=false; BEGIN PERFORM public.prime_answer('اهلا'); EXCEPTION WHEN SQLSTATE '42501' THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'anonymous call accepted'; END IF;

  PERFORM set_config('request.jwt.claim.sub', v_cust::text, true);
  -- normalization
  IF private.prime_normalize('أهلًا ٢٠') <> 'اهلا 20' THEN RAISE EXCEPTION 'normalize: %', private.prime_normalize('أهلًا ٢٠'); END IF;
  IF private.prime_stem('الكهرباء والسباكة') <> 'كهرباء سباكه' THEN RAISE EXCEPTION 'stem: %', private.prime_stem('الكهرباء والسباكة'); END IF;
  -- greeting uses first name
  v_r := public.prime_answer('اهلاً');
  IF v_r->>'intent' <> 'greeting' OR jsonb_array_length(v_r->'suggestions') < 3 THEN RAISE EXCEPTION 'greeting: %', v_r; END IF;
  -- colloquial and spelling variants map to a service
  v_r := public.prime_answer('عايز مواسرجي');
  IF v_r->>'answer' NOT LIKE '%سباكة%' THEN RAISE EXCEPTION 'synonym service: %', v_r; END IF;
  v_r := public.prime_answer('بكام التكيف');
  IF v_r->>'answer' NOT LIKE '%تكييف%' OR v_r->>'intent' <> 'price' THEN RAISE EXCEPTION 'price service: %', v_r; END IF;
  -- a brand new service is picked up automatically
  INSERT INTO public.services (category_id, name_ar, is_active) SELECT category_id, 'خدمة اختبار برايم', true FROM public.services LIMIT 1;
  v_r := public.prime_answer('عايز خدمة اختبار برايم');
  IF v_r->>'answer' NOT LIKE '%خدمة اختبار برايم%' THEN RAISE EXCEPTION 'new service not picked up: %', v_r; END IF;
  -- customer tracking own orders
  v_r := public.prime_answer('فين طلبي');
  IF v_r->>'intent' <> 'order_track' OR v_r->>'answer' NOT LIKE 'آخر طلباتك%' THEN RAISE EXCEPTION 'track: %', v_r; END IF;
  -- wallet
  v_r := public.prime_answer('رصيدي كام');
  IF v_r->>'intent' <> 'wallet' OR v_r->>'answer' NOT LIKE '%EGP%' THEN RAISE EXCEPTION 'wallet: %', v_r; END IF;
  -- customer never gets staff data
  v_r := public.prime_answer('ملخص الطلبات');
  IF v_r->>'answer' LIKE 'الطلبات دلوقتي%' THEN RAISE EXCEPTION 'customer saw staff summary'; END IF;
  -- customer must not see commission wording
  IF public.prime_answer('كام العمولة')::text LIKE '%عمولة%' AND public.prime_answer('كام العمولة')->>'matched' = 'true' AND public.prime_answer('كام العمولة')->>'answer' LIKE '%EGP%' THEN RAISE EXCEPTION 'commission leak'; END IF;
  -- knowledge base answers a platform question
  v_r := public.prime_answer('ما هي وصلة');
  IF v_r->>'matched' <> 'true' THEN RAISE EXCEPTION 'what_is: %', v_r; END IF;
  -- unknown question is logged, count increments
  v_r := public.prime_answer('كلمات غريبة زززكككيييل');
  IF v_r->>'matched' <> 'false' THEN RAISE EXCEPTION 'unknown matched: %', v_r; END IF;
  PERFORM public.prime_answer('كلمات غريبة زززكككيييل');
  SELECT asked_count INTO v_n FROM private.prime_unanswered WHERE question LIKE 'كلمات غريبة%';
  IF v_n <> 2 THEN RAISE EXCEPTION 'unanswered count %', v_n; END IF;
  -- too long / empty refused
  v_ok:=false; BEGIN PERFORM public.prime_answer(repeat('ا',501)); EXCEPTION WHEN SQLSTATE '22023' THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'long message accepted'; END IF;
  v_ok:=false; BEGIN PERFORM public.prime_answer('   '); EXCEPTION WHEN SQLSTATE '22023' THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'empty accepted'; END IF;

  -- provider: own orders only, role suggestions
  PERFORM set_config('request.jwt.claim.sub', v_prov::text, true);
  v_r := public.prime_answer('طلباتي');
  IF v_r->>'answer' NOT LIKE 'طلباتك:%' THEN RAISE EXCEPTION 'provider orders: %', v_r; END IF;
  IF v_r->'suggestions'->>0 <> 'طلباتي' THEN RAISE EXCEPTION 'provider suggestions'; END IF;
  v_r := public.prime_answer('رصيدي');
  IF v_r->>'answer' LIKE 'رصيد محفظتك%' THEN RAISE EXCEPTION 'provider got customer wallet'; END IF;

  -- owner: staff summary
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  v_r := public.prime_answer('ملخص الطلبات');
  IF v_r->>'answer' NOT LIKE 'الطلبات دلوقتي%' THEN RAISE EXCEPTION 'owner summary: %', v_r; END IF;
  v_r := public.prime_answer('الشكاوى المفتوحة');
  IF v_r->>'answer' NOT LIKE 'الشكاوى المفتوحة دلوقتي%' THEN RAISE EXCEPTION 'owner complaints: %', v_r; END IF;

  -- staff without requests.view gets no summary
  PERFORM set_config('request.jwt.claim.sub', (SELECT p.id::text FROM public.profiles p WHERE p.role='staff' AND p.status='active' AND NOT EXISTS (SELECT 1 FROM public.staff_permissions sp WHERE sp.user_id=p.id AND sp.is_active AND 'requests.view'=ANY(sp.permissions)) LIMIT 1), true);
  IF current_setting('request.jwt.claim.sub') <> '' THEN
    v_r := public.prime_answer('ملخص الطلبات');
    IF v_r->>'answer' LIKE 'الطلبات دلوقتي%' THEN RAISE EXCEPTION 'staff without permission saw summary'; END IF;
  END IF;


  -- ===== role filtering: every role only sees actions that belong to it =====
  SELECT p.id INTO v_staff FROM public.profiles p WHERE p.role='staff' AND p.status='active'
    AND NOT EXISTS (SELECT 1 FROM public.staff_permissions sp WHERE sp.user_id=p.id AND 'requests.view'=ANY(sp.permissions)) ORDER BY p.created_at LIMIT 1;
  IF v_staff IS NULL THEN RAISE EXCEPTION 'staff fixture missing'; END IF;
  -- staff without any permission: no customer actions, no staff data, no order creation text
  PERFORM set_config('request.jwt.claim.sub', v_staff::text, true);
  v_r := public.prime_answer('اهلا');
  v_sugg := v_r->'suggestions';
  IF v_sugg ?| ARRAY['تابع طلبي','أسعار الخدمات','رصيد محفظتي','عايز أقدم شكوى','طلباتي','ملخص الطلبات','الشكاوى المفتوحة','الأدوار والصلاحيات'] THEN RAISE EXCEPTION 'staff (no perms) suggestions: %', v_sugg; END IF;
  FOREACH v_svc IN ARRAY ARRAY['عايز اطلب سباك','ازاي اطلب خدمة','الغي الطلب','رصيدي','اسجل كمزود','ملخص الطلبات','الشكاوى المفتوحة'] LOOP
    v_r := public.prime_answer(v_svc);
    IF v_r->>'matched' = 'true' AND v_r->>'intent' NOT IN ('service','knowledge') THEN RAISE EXCEPTION 'staff (no perms) got an answer for %: %', v_svc, v_r; END IF;
    IF v_r->>'answer' LIKE '%الصفحة الرئيسية%' OR v_r->>'answer' LIKE '%رصيد محفظتك%' OR v_r->>'answer' LIKE 'الطلبات دلوقتي%' OR v_r->>'answer' LIKE 'الشكاوى المفتوحة دلوقتي%' THEN RAISE EXCEPTION 'staff (no perms) leak for %: %', v_svc, v_r; END IF;
  END LOOP;
  v_r := public.prime_answer('عايز اطلب سباك');
  IF v_r->>'answer' LIKE '%اطلب%' AND v_r->>'answer' LIKE '%طلبك%' THEN RAISE EXCEPTION 'staff sees order creation text: %', v_r; END IF;
  -- staff with requests.view (granted only inside this rolled-back transaction): summary yes, higher-level and customer items no
  UPDATE public.staff_permissions SET permissions = array_append(permissions,'requests.view'), is_active = true WHERE user_id = v_staff;
  v_r := public.prime_answer('اهلا');
  IF NOT (v_r->'suggestions' ? 'ملخص الطلبات') THEN RAISE EXCEPTION 'staff with requests.view lacks summary'; END IF;
  IF v_r->'suggestions' ?| ARRAY['الأدوار والصلاحيات','الشكاوى المفتوحة','تابع طلبي','عايز أقدم شكوى','رصيد محفظتي'] THEN RAISE EXCEPTION 'staff suggestions exceed role: %', v_r->'suggestions'; END IF;
  IF public.prime_answer('ملخص الطلبات')->>'answer' NOT LIKE 'الطلبات دلوقتي%' THEN RAISE EXCEPTION 'staff summary missing'; END IF;
  IF public.prime_answer('الشكاوى المفتوحة')->>'answer' LIKE 'الشكاوى المفتوحة دلوقتي%' THEN RAISE EXCEPTION 'staff saw complaints without support.view'; END IF;
  -- customer: no staff items; provider: no customer or staff items; owner sees the admin items
  PERFORM set_config('request.jwt.claim.sub', v_cust::text, true);
  v_sugg := public.prime_answer('اهلا')->'suggestions';
  IF v_sugg ?| ARRAY['ملخص الطلبات','الشكاوى المفتوحة','الأدوار والصلاحيات','طلباتي','شكاوى العملاء'] THEN RAISE EXCEPTION 'customer suggestions exceed role: %', v_sugg; END IF;
  IF public.prime_answer('ملخص الطلبات')->>'matched' = 'true' THEN RAISE EXCEPTION 'customer matched staff intent'; END IF;
  PERFORM set_config('request.jwt.claim.sub', v_prov::text, true);
  v_sugg := public.prime_answer('اهلا')->'suggestions';
  IF v_sugg ?| ARRAY['ملخص الطلبات','الشكاوى المفتوحة','الأدوار والصلاحيات','تابع طلبي','رصيد محفظتي','عايز أقدم شكوى'] THEN RAISE EXCEPTION 'provider suggestions exceed role: %', v_sugg; END IF;
  FOREACH v_svc IN ARRAY ARRAY['عايز اطلب سباك','الغي الطلب','اسجل كمزود','رصيدي'] LOOP
    v_r := public.prime_answer(v_svc);
    IF v_r->>'answer' LIKE '%الصفحة الرئيسية%' OR v_r->>'answer' LIKE 'رصيد محفظتك%' OR v_r->>'answer' LIKE '%تلغي طلبك%' OR v_r->>'answer' LIKE '%تسجل كمزود%' THEN RAISE EXCEPTION 'provider leak for %: %', v_svc, v_r; END IF;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  v_sugg := public.prime_answer('اهلا')->'suggestions';
  IF NOT (v_sugg ?& ARRAY['ملخص الطلبات','الشكاوى المفتوحة','الأدوار والصلاحيات']) OR v_sugg ?| ARRAY['تابع طلبي','رصيد محفظتي','عايز أقدم شكوى'] THEN RAISE EXCEPTION 'owner suggestions: %', v_sugg; END IF;

  -- API roles cannot touch the tables or helpers
  IF has_function_privilege('anon','public.prime_answer(text)','EXECUTE') THEN RAISE EXCEPTION 'anon can execute'; END IF;
  IF has_table_privilege('authenticated','private.prime_unanswered','SELECT') OR has_table_privilege('authenticated','private.prime_synonyms','SELECT') THEN RAISE EXCEPTION 'tables exposed'; END IF;
  RAISE NOTICE 'P3 tests passed';
END;
$test$;
ROLLBACK;
