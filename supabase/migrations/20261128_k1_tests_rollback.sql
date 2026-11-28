-- K1 ROLLBACK tests. Run AFTER W1 and 20261128_k1_complaints.sql. Everything is rolled back.
BEGIN;
DO $test$
DECLARE
  v_req uuid; v_cust uuid; v_other uuid; v_staff uuid; v_nostaff uuid; v_owner uuid;
  v_res jsonb; v_c1 uuid; v_c2 uuid; v_c3 uuid; v_ok boolean; v_n bigint;
  v_rev_before numeric; v_rev_after numeric; v_cnt_before bigint; v_cnt_after bigint;
  v_notif_before bigint; v_cron_before bigint; v_code text; v_bal numeric; v_bal0 numeric := 0;
BEGIN
  IF has_function_privilege('anon','public.create_complaint(uuid,text,text)','EXECUTE')
     OR has_function_privilege('anon','public.my_complaints()','EXECUTE')
     OR has_function_privilege('anon','public.staff_list_complaints(text,integer,integer)','EXECUTE')
     OR has_function_privilege('anon','public.staff_get_complaint(uuid)','EXECUTE')
     OR has_function_privilege('anon','public.staff_resolve_complaint(uuid,text,text,numeric,text)','EXECUTE')
     OR has_function_privilege('anon','public.staff_reject_complaint(uuid,text)','EXECUTE')
     OR has_function_privilege('anon','public.staff_assign_complaint(uuid,uuid)','EXECUTE')
     OR has_function_privilege('anon','public.staff_add_complaint_note(uuid,text)','EXECUTE')
     OR has_function_privilege('anon','public.add_complaint_photo(uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'anon can execute a K1 function';
  END IF;
  IF has_table_privilege('authenticated','public.complaints','SELECT') OR has_table_privilege('authenticated','public.complaint_events','SELECT')
     OR has_table_privilege('authenticated','public.complaint_photos','SELECT') OR has_table_privilege('anon','public.complaints','SELECT') THEN
    RAISE EXCEPTION 'complaint tables not locked';
  END IF;
  IF has_function_privilege('authenticated','private.complaint_comp_cap()','EXECUTE') THEN RAISE EXCEPTION 'helper exposed'; END IF;

  PERFORM set_config('request.jwt.claim.sub','',true);
  SELECT sr.id, sr.customer_id INTO v_req, v_cust FROM public.service_requests sr
   JOIN public.profiles p ON p.id = sr.customer_id AND p.status = 'active'
   WHERE sr.status = 'completed' AND sr.provider_id IS NOT NULL ORDER BY sr.created_at LIMIT 1;
  IF v_req IS NULL THEN RAISE EXCEPTION 'prerequisite missing: completed request with provider'; END IF;
  SELECT id INTO v_other FROM public.profiles WHERE role='customer' AND status='active' AND id <> v_cust ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_staff FROM public.profiles p JOIN public.staff_permissions sp ON sp.user_id=p.id AND sp.is_active
   WHERE p.role='staff' AND p.status='active' AND p.staff_role_code='ASV' ORDER BY p.created_at LIMIT 1;
  SELECT p.id INTO v_nostaff FROM public.profiles p JOIN public.staff_permissions sp ON sp.user_id=p.id AND sp.is_active
   WHERE p.role='staff' AND p.status='active' AND p.id <> v_staff AND NOT ('support.manage' = ANY(sp.permissions)) AND NOT ('support.view' = ANY(sp.permissions))
   ORDER BY p.created_at LIMIT 1;
  SELECT id INTO v_owner FROM public.profiles WHERE role='owner' AND status='active' LIMIT 1;
  IF v_other IS NULL OR v_staff IS NULL OR v_owner IS NULL THEN RAISE EXCEPTION 'prerequisite missing: identities'; END IF;

  SELECT coalesce(sum(average_rating),0), count(*) INTO v_rev_before, v_cnt_before FROM public.provider_profiles;
  SELECT count(*) INTO v_n FROM public.reviews; v_cnt_before := v_cnt_before + v_n;
  SELECT count(*) INTO v_notif_before FROM public.notifications;
  SELECT count(*) INTO v_cron_before FROM cron.job;

  PERFORM set_config('request.jwt.claim.sub', v_cust::text, true);
  v_bal0 := (public.get_my_customer_wallet()->>'balance')::numeric;
  -- customer files a complaint
  PERFORM set_config('request.jwt.claim.sub', v_cust::text, true);
  v_ok := false;
  BEGIN PERFORM public.create_complaint(v_req, 'service_quality', 'short'); EXCEPTION WHEN SQLSTATE '22023' THEN v_ok := true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'short description accepted'; END IF;
  v_ok := false;
  BEGIN PERFORM public.create_complaint(v_req, 'bogus_category', 'a long enough description'); EXCEPTION WHEN check_violation THEN v_ok := true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'bad category accepted'; END IF;
  v_res := public.create_complaint(v_req, 'service_quality', 'a long enough description of the problem');
  v_c1 := (v_res->>'id')::uuid;
  v_ok := false;
  BEGIN PERFORM public.create_complaint(v_req, 'other', 'second one while first is open'); EXCEPTION WHEN SQLSTATE '22023' THEN v_ok := true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'duplicate open complaint accepted'; END IF;
  PERFORM public.add_complaint_photo(v_c1, 'complaints/test/photo1.jpg');

  -- another customer cannot file on this request nor see it
  PERFORM set_config('request.jwt.claim.sub', v_other::text, true);
  v_ok := false;
  BEGIN PERFORM public.create_complaint(v_req, 'other', 'not my request at all really'); EXCEPTION WHEN SQLSTATE '22023' THEN v_ok := true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'other customer filed on foreign request'; END IF;
  IF jsonb_array_length(public.my_complaints()) <> 0 THEN RAISE EXCEPTION 'other customer sees foreign complaints'; END IF;
  v_ok := false;
  BEGIN PERFORM public.add_complaint_photo(v_c1, 'x/y.jpg'); EXCEPTION WHEN SQLSTATE '42501' THEN v_ok := true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'foreign photo upload accepted'; END IF;

  -- staff without support permissions
  IF v_nostaff IS NOT NULL THEN
    PERFORM set_config('request.jwt.claim.sub', v_nostaff::text, true);
    v_ok := false;
    BEGIN PERFORM public.staff_list_complaints(NULL, 10, 0); EXCEPTION WHEN SQLSTATE '42501' THEN v_ok := true; END;
    IF NOT v_ok THEN RAISE EXCEPTION 'staff without permission listed complaints'; END IF;
  END IF;

  -- ASV with support.manage
  PERFORM set_config('request.jwt.claim.sub','',true);
  UPDATE public.staff_permissions SET permissions = array_append(permissions,'support.manage')
   WHERE user_id = v_staff AND NOT ('support.manage' = ANY(permissions));
  PERFORM set_config('request.jwt.claim.sub', v_staff::text, true);
  IF jsonb_array_length(public.staff_list_complaints('open', 10, 0)) < 1 THEN RAISE EXCEPTION 'staff cannot list open complaints'; END IF;
  v_res := public.staff_get_complaint(v_c1);
  IF (v_res->>'comp_cap')::numeric <> 200 OR (v_res->>'can_fund_by_provider')::boolean THEN RAISE EXCEPTION 'ASV cap or funding flag wrong'; END IF;
  IF jsonb_array_length(v_res->'photos') <> 1 OR jsonb_array_length(v_res->'events') < 2 THEN RAISE EXCEPTION 'detail incomplete'; END IF;
  PERFORM public.staff_add_complaint_note(v_c1, 'internal note about the case');
  IF (SELECT status FROM public.complaints WHERE id = v_c1) <> 'in_review' THEN RAISE EXCEPTION 'note did not move to in_review'; END IF;

  v_ok := false;
  BEGIN PERFORM public.staff_resolve_complaint(v_c1, 'refund given to customer', 'wallet_credit', 250, 'platform'); EXCEPTION WHEN SQLSTATE '42501' THEN v_ok := true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'ASV exceeded the 200 limit'; END IF;
  v_ok := false;
  BEGIN PERFORM public.staff_resolve_complaint(v_c1, 'refund given to customer', 'discount_code', 100, 'provider'); EXCEPTION WHEN SQLSTATE '42501' THEN v_ok := true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'ASV chose provider funding'; END IF;
  v_ok := false;
  BEGIN PERFORM public.staff_resolve_complaint(v_c1, 'refund given to customer', 'wallet_credit', 100, 'provider'); EXCEPTION WHEN SQLSTATE '42501' OR SQLSTATE '22023' THEN v_ok := true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'wallet credit accepted with provider funding'; END IF;
  v_res := public.staff_resolve_complaint(v_c1, 'wallet credit given to customer', 'wallet_credit', 150, 'platform');
  IF v_res->>'status' <> 'resolved' THEN RAISE EXCEPTION 'resolve failed'; END IF;
  v_ok := false;
  BEGIN PERFORM public.staff_resolve_complaint(v_c1, 'second resolve attempt', 'none', NULL, NULL); EXCEPTION WHEN SQLSTATE '22023' THEN v_ok := true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'closed complaint resolved twice'; END IF;

  -- customer sees the compensation, not the funding
  PERFORM set_config('request.jwt.claim.sub', v_cust::text, true);
  v_res := public.my_complaints();
  IF v_res->0->>'status' <> 'resolved' OR (v_res->0->>'compensation_amount')::numeric <> 150 OR v_res->0->>'compensation_type' <> 'wallet_credit' THEN
    RAISE EXCEPTION 'customer view wrong';
  END IF;
  IF v_res->0 ? 'compensation_funded_by' OR v_res->0 ? 'assigned_to' OR v_res->0 ? 'resolved_by' THEN RAISE EXCEPTION 'customer view leaks internals'; END IF;
  v_bal := (public.get_my_customer_wallet()->>'balance')::numeric;
  IF v_bal - v_bal0 <> 150 THEN RAISE EXCEPTION 'wallet balance not credited: %', v_bal; END IF;

  -- second complaint, discount code path, as OPS
  v_res := public.create_complaint(v_req, 'no_show', 'a new problem after the first resolution');
  v_c2 := (v_res->>'id')::uuid;
  PERFORM set_config('request.jwt.claim.sub','',true);
  UPDATE public.profiles SET staff_role_code = 'OPS', staff_title = 'العمليات' WHERE id = v_staff;
  PERFORM set_config('request.jwt.claim.sub', v_staff::text, true);
  IF (public.staff_get_complaint(v_c2)->>'comp_cap')::numeric <> 500 OR NOT (public.staff_get_complaint(v_c2)->>'can_fund_by_provider')::boolean THEN
    RAISE EXCEPTION 'OPS cap or funding flag wrong';
  END IF;
  v_ok := false;
  BEGIN PERFORM public.staff_resolve_complaint(v_c2, 'too much compensation', 'discount_code', 600, 'platform'); EXCEPTION WHEN SQLSTATE '42501' THEN v_ok := true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'OPS exceeded the 500 limit'; END IF;
  PERFORM public.staff_resolve_complaint(v_c2, 'discount code issued, provider pays', 'discount_code', 300, 'provider');
  SELECT pr.code INTO v_code FROM public.promotions pr JOIN public.complaints c ON c.compensation_ref = pr.id WHERE c.id = v_c2
     AND pr.usage_limit = 1 AND pr.per_user_limit = 1 AND pr.discount_type = 'fixed' AND pr.discount_value = 300 AND pr.funded_by = 'provider' AND pr.is_active;
  IF v_code IS NULL THEN RAISE EXCEPTION 'discount code not created correctly'; END IF;
  PERFORM set_config('request.jwt.claim.sub', v_cust::text, true);
  IF (SELECT e->>'compensation_code' FROM jsonb_array_elements(public.my_complaints()) e WHERE (e->>'id')::uuid = v_c2) IS DISTINCT FROM v_code THEN RAISE EXCEPTION 'customer does not see the code'; END IF;

  -- reject path and owner uncapped
  v_res := public.create_complaint(v_req, 'other', 'third complaint to be rejected later');
  v_c3 := (v_res->>'id')::uuid;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  IF (public.staff_get_complaint(v_c3)->>'comp_cap')::numeric < 1000000 THEN RAISE EXCEPTION 'owner is capped'; END IF;
  PERFORM public.staff_assign_complaint(v_c3, v_staff);
  PERFORM public.staff_reject_complaint(v_c3, 'not supported by the facts');
  IF (SELECT status FROM public.complaints WHERE id = v_c3) <> 'rejected' THEN RAISE EXCEPTION 'reject failed'; END IF;
  v_ok := false;
  BEGIN PERFORM public.staff_add_complaint_note(v_c3, 'note after closing'); EXCEPTION WHEN SQLSTATE '22023' THEN v_ok := true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'note on closed complaint accepted'; END IF;

  -- no rating impact, no notifications, no cron jobs
  PERFORM set_config('request.jwt.claim.sub','',true);
  SELECT coalesce(sum(average_rating),0), count(*) INTO v_rev_after, v_cnt_after FROM public.provider_profiles;
  SELECT count(*) INTO v_n FROM public.reviews; v_cnt_after := v_cnt_after + v_n;
  IF v_rev_after <> v_rev_before OR v_cnt_after <> v_cnt_before THEN RAISE EXCEPTION 'ratings or reviews changed'; END IF;
  IF (SELECT count(*) FROM public.notifications) <> v_notif_before THEN RAISE EXCEPTION 'notifications were created'; END IF;
  IF (SELECT count(*) FROM cron.job) <> v_cron_before THEN RAISE EXCEPTION 'cron job count changed'; END IF;

  RAISE NOTICE 'K1 tests passed';
END;
$test$;
ROLLBACK;
