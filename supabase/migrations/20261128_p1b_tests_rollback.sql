BEGIN;
DO $test$
DECLARE v_cust uuid; v_prov uuid; v_owner uuid; v_staff uuid; v_r jsonb; v_ok boolean; v_sid uuid; v_uid uuid; v_cnt integer; v_syn bigint;
  rec record;
BEGIN
  SELECT customer_id INTO v_cust FROM public.service_requests LIMIT 1;
  SELECT pp.user_id INTO v_prov FROM public.provider_profiles pp JOIN public.profiles p ON p.id=pp.user_id WHERE p.status='active' LIMIT 1;
  SELECT p.id INTO v_owner FROM public.profiles p WHERE p.id::text LIKE '2213f856%';
  SELECT p.id INTO v_staff FROM public.profiles p WHERE p.role='staff' AND p.status='active'
    AND NOT EXISTS (SELECT 1 FROM public.staff_permissions sp WHERE sp.user_id=p.id AND sp.is_active AND 'services.manage'=ANY(sp.permissions)) ORDER BY p.created_at LIMIT 1;
  IF v_cust IS NULL OR v_prov IS NULL OR v_owner IS NULL OR v_staff IS NULL THEN RAISE EXCEPTION 'fixtures missing'; END IF;
  SELECT count(*) INTO v_syn FROM private.prime_synonyms;
  IF v_syn < 6000 THEN RAISE EXCEPTION 'dictionary not loaded: %', v_syn; END IF;

  PERFORM set_config('request.jwt.claim.sub', v_cust::text, true);
  -- Franco-Arab, colloquial, request phrasings
  FOR rec IN SELECT * FROM (VALUES
     ('3ayez sabak','سباكة'),('عايز حد يصلح السخان','سخانات'),('محتاج سباك بكرة','سباكة'),('a7tag kahraba','كهرباء'),
     ('عايز تكييف يتصلح','تكييف'),('3awez takeef','تكييف'),('عايز دكتور اطفال','زيارة طبيب'),('محتاج مصور فرح','تصوير'),
     ('3ayez lawyer','محاماة'),('محتاجه جليسة اطفال','جليسة أطفال'),('عايز حد يركب كاميرات مراقبة','كاميرات مراقبة'),
     ('3ayez hairdresser','كوافير'),('محتاج ممرضة تيجي البيت','تمريض منزلي'),('عايز نجار','نجارة'),('عايز مكوجي','كي ملابس'),
     ('بكام الكهربائي','كهرباء'),('bekam sabak','سباكة'),('عاوز مترجم معتمد','ترجمة')
  ) t(q, s) LOOP
    v_r := public.prime_answer(rec.q);
    IF v_r->>'answer' NOT LIKE '%' || rec.s || '%' THEN RAISE EXCEPTION 'phrase "%" expected % got %', rec.q, rec.s, v_r->>'answer'; END IF;
  END LOOP;
  -- cities and neighborhoods map to their city
  v_r := public.prime_answer('عايز سباك في سموحة');
  IF v_r->>'answer' NOT LIKE '%الاسكندرية%' THEN RAISE EXCEPTION 'neighborhood: %', v_r; END IF;
  v_r := public.prime_answer('3ayez sabak fi alex');
  IF v_r->>'answer' NOT LIKE '%الاسكندرية%' THEN RAISE EXCEPTION 'arabizi city: %', v_r; END IF;
  v_r := public.prime_answer('محتاج كهربائي في مدينة نصر');
  IF v_r->>'answer' NOT LIKE '%القاهرة%' THEN RAISE EXCEPTION 'nasr city: %', v_r; END IF;
  v_r := public.prime_answer('عايز سباك في الجناين');
  IF v_r->>'answer' NOT LIKE '%السويس%' THEN RAISE EXCEPTION 'area from geo_areas: %', v_r; END IF;
  -- a section lists its services
  v_r := public.prime_answer('ايه في قسم خدمات شخصية');
  IF v_r->>'intent' <> 'category' THEN RAISE EXCEPTION 'category: %', v_r; END IF;
  -- english name of a service is picked up automatically
  v_r := public.prime_answer('i need plumbing');
  IF v_r->>'answer' NOT LIKE '%سباكة%' THEN RAISE EXCEPTION 'name_en: %', v_r; END IF;
  -- intents in colloquial / arabizi
  v_r := public.prime_answer('فين طلبي');
  IF v_r->>'intent' <> 'order_track' THEN RAISE EXCEPTION 'track: %', v_r; END IF;
  v_r := public.prime_answer('fein talaby');
  IF v_r->>'intent' <> 'order_track' THEN RAISE EXCEPTION 'track arabizi: %', v_r; END IF;
  v_r := public.prime_answer('ma7fazty kam');
  IF v_r->>'intent' <> 'wallet' THEN RAISE EXCEPTION 'wallet arabizi: %', v_r; END IF;
  v_r := public.prime_answer('3ayez ashtaky');
  IF v_r->>'intent' <> 'complaint' THEN RAISE EXCEPTION 'complaint arabizi: %', v_r; END IF;
  v_r := public.prime_answer('ezayak ya prime');
  IF v_r->>'intent' <> 'greeting' THEN RAISE EXCEPTION 'greeting: %', v_r; END IF;
  v_r := public.prime_answer('shokran awy');
  IF v_r->>'intent' <> 'thanks' THEN RAISE EXCEPTION 'thanks: %', v_r; END IF;

  -- role rules still hold: provider and staff never get customer-only actions or staff data
  PERFORM set_config('request.jwt.claim.sub', v_prov::text, true);
  v_r := public.prime_answer('3ayez a6lob sabak');
  IF v_r->>'answer' LIKE '%من الصفحة الرئيسية%' THEN RAISE EXCEPTION 'provider got customer order flow: %', v_r; END IF;
  v_r := public.prime_answer('ma7fazty kam');
  IF v_r->>'answer' LIKE 'رصيد محفظتك%' THEN RAISE EXCEPTION 'provider saw wallet: %', v_r; END IF;
  PERFORM set_config('request.jwt.claim.sub', v_staff::text, true);
  v_r := public.prime_answer('ملخص الطلبات');
  IF v_r->>'answer' LIKE 'رصيد محفظتك%' THEN RAISE EXCEPTION 'staff saw wallet'; END IF;
  v_r := public.prime_answer('3ayez a6lob sabak');
  IF v_r->>'answer' LIKE '%من الصفحة الرئيسية%' THEN RAISE EXCEPTION 'staff got customer order flow: %', v_r; END IF;

  -- admin functions refused for non-admins
  FOREACH v_uid IN ARRAY ARRAY[v_cust, v_prov, v_staff] LOOP
    PERFORM set_config('request.jwt.claim.sub', v_uid::text, true);
    v_ok := false; BEGIN PERFORM public.prime_admin_list_unanswered(10); EXCEPTION WHEN SQLSTATE '42501' THEN v_ok := true; END;
    IF NOT v_ok THEN RAISE EXCEPTION 'list_unanswered open to %', v_uid; END IF;
    v_ok := false; BEGIN PERFORM public.prime_admin_suggest_keywords('خدمة'); EXCEPTION WHEN SQLSTATE '42501' THEN v_ok := true; END;
    IF NOT v_ok THEN RAISE EXCEPTION 'suggest open to %', v_uid; END IF;
    v_ok := false; BEGIN PERFORM public.prime_admin_add_synonyms(gen_random_uuid(), ARRAY['x y z']); EXCEPTION WHEN SQLSTATE '42501' THEN v_ok := true; END;
    IF NOT v_ok THEN RAISE EXCEPTION 'add_synonyms open to %', v_uid; END IF;
    v_ok := false; BEGIN PERFORM public.prime_admin_resolve_unanswered(gen_random_uuid(), NULL); EXCEPTION WHEN SQLSTATE '42501' THEN v_ok := true; END;
    IF NOT v_ok THEN RAISE EXCEPTION 'resolve open to %', v_uid; END IF;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  v_ok := false; BEGIN PERFORM public.prime_admin_list_unanswered(10); EXCEPTION WHEN SQLSTATE '42501' THEN v_ok := true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'anonymous admin call accepted'; END IF;

  -- admin flow: new service -> suggested keywords -> add -> recognized; unanswered -> resolve -> learned
  INSERT INTO public.services (category_id, name_ar, is_active) SELECT category_id, 'خدمة اختبار برايم', true FROM public.services LIMIT 1 RETURNING id INTO v_sid;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  v_r := public.prime_admin_suggest_keywords('خدمة اختبار برايم');
  IF jsonb_array_length(v_r) < 8 THEN RAISE EXCEPTION 'suggested set too small: %', v_r; END IF;
  v_cnt := public.prime_admin_add_synonyms(v_sid, ARRAY['زيطة اختبار','zeita test']);
  IF v_cnt <> 2 THEN RAISE EXCEPTION 'add_synonyms count %', v_cnt; END IF;
  PERFORM set_config('request.jwt.claim.sub', v_cust::text, true);
  v_r := public.prime_answer('عايز زيطة اختبار');
  IF v_r->>'answer' NOT LIKE '%خدمة اختبار برايم%' THEN RAISE EXCEPTION 'added synonym not used: %', v_r; END IF;
  v_r := public.prime_answer('كلمة غريبة جدا قرقوشة');
  IF v_r->>'matched' <> 'false' THEN RAISE EXCEPTION 'should be unanswered: %', v_r; END IF;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  v_r := public.prime_admin_list_unanswered(500);
  IF v_r::text NOT LIKE '%قرقوشة%' THEN RAISE EXCEPTION 'unanswered not listed'; END IF;
  SELECT (e->>'id')::uuid INTO v_uid FROM jsonb_array_elements(v_r) e WHERE e->>'question' LIKE '%قرقوشة%' LIMIT 1;
  v_r := public.prime_admin_resolve_unanswered(v_uid, v_sid);
  IF NOT (v_r->>'synonym_added')::boolean THEN RAISE EXCEPTION 'resolve did not add synonym: %', v_r; END IF;
  PERFORM set_config('request.jwt.claim.sub', v_cust::text, true);
  v_r := public.prime_answer('كلمة غريبة جدا قرقوشة');
  IF v_r->>'answer' NOT LIKE '%خدمة اختبار برايم%' THEN RAISE EXCEPTION 'resolved phrase not learned: %', v_r; END IF;
  RAISE NOTICE 'P1b tests passed';
END
$test$;
ROLLBACK;
