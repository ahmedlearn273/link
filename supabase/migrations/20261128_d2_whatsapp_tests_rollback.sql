-- Tests for 20261128_d2_whatsapp.sql. Everything is rolled back.
BEGIN;
DO $test$
DECLARE v_c uuid; v_other uuid; v_other_wa text; v_ok boolean; v_new uuid := gen_random_uuid(); v_new2 uuid := gen_random_uuid(); v_wa text; v_n bigint;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','',true);
  IF has_function_privilege('anon','public.update_my_whatsapp(text)','EXECUTE') THEN RAISE EXCEPTION 'anon can execute'; END IF;
  SELECT id INTO v_c FROM public.profiles WHERE role='customer' AND status='active' ORDER BY created_at LIMIT 1;
  SELECT id, whatsapp_number INTO v_other, v_other_wa FROM public.profiles WHERE role='customer' AND id<>v_c ORDER BY created_at LIMIT 1;
  PERFORM set_config('request.jwt.claim.sub',v_c::text,true);
  PERFORM public.update_my_whatsapp('+201012345678');
  SELECT whatsapp_number INTO v_wa FROM public.profiles WHERE id=v_c;
  IF v_wa IS DISTINCT FROM '+201012345678' THEN RAISE EXCEPTION 'number not stored'; END IF;
  IF (SELECT whatsapp_number FROM public.profiles WHERE id=v_other) IS DISTINCT FROM v_other_wa THEN RAISE EXCEPTION 'someone else changed'; END IF;
  v_ok:=false; BEGIN PERFORM public.update_my_whatsapp('0101234'); EXCEPTION WHEN SQLSTATE '22023' THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'bad format accepted'; END IF;
  v_ok:=false; BEGIN PERFORM public.update_my_whatsapp(''); EXCEPTION WHEN SQLSTATE '22023' THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'empty accepted'; END IF;
  PERFORM set_config('request.jwt.claim.sub','',true);
  v_ok:=false; BEGIN PERFORM public.update_my_whatsapp('+201012345678'); EXCEPTION WHEN SQLSTATE '42501' THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'anon/no-uid accepted'; END IF;
  UPDATE public.profiles SET status='suspended', suspension_previous_status='active', suspended_at=now(), suspension_reason='test' WHERE id=v_c;
  PERFORM set_config('request.jwt.claim.sub',v_c::text,true);
  v_ok:=false; BEGIN PERFORM public.update_my_whatsapp('+201112345678'); EXCEPTION WHEN SQLSTATE '42501' THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'suspended accepted'; END IF;
  -- signup trigger
  PERFORM set_config('request.jwt.claim.sub','',true);
  INSERT INTO auth.users (id, aud, role, email, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
  VALUES (v_new,'authenticated','authenticated','wa-test-1@example.invalid','{"full_name":"WA Test","whatsapp_number":"+201212345678"}'::jsonb,'{}'::jsonb,now(),now());
  SELECT whatsapp_number INTO v_wa FROM public.profiles WHERE id=v_new;
  IF v_wa IS DISTINCT FROM '+201212345678' THEN RAISE EXCEPTION 'signup did not store whatsapp'; END IF;
  v_ok:=false;
  BEGIN
    INSERT INTO auth.users (id, aud, role, email, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
    VALUES (v_new2,'authenticated','authenticated','wa-test-2@example.invalid','{"full_name":"No WA"}'::jsonb,'{}'::jsonb,now(),now());
  EXCEPTION WHEN SQLSTATE '22023' THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'signup without whatsapp was accepted'; END IF;
  v_ok:=false;
  BEGIN
    INSERT INTO auth.users (id, aud, role, email, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
    VALUES (v_new2,'authenticated','authenticated','wa-test-3@example.invalid','{"whatsapp_number":"12345"}'::jsonb,'{}'::jsonb,now(),now());
  EXCEPTION WHEN SQLSTATE '22023' THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'signup with bad whatsapp was accepted'; END IF;
  -- staff created by the platform is exempt
  INSERT INTO auth.users (id, aud, role, email, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
  VALUES (v_new2,'authenticated','authenticated','wa-test-4@example.invalid','{"full_name":"Staff Test"}'::jsonb,'{"account_role":"staff"}'::jsonb,now(),now());
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=v_new2 AND role='staff') THEN RAISE EXCEPTION 'staff signup affected'; END IF;
  SELECT count(*) INTO v_n FROM public.profiles WHERE role IN ('customer','provider') AND whatsapp_number IS NULL AND id NOT IN (v_new);
  RAISE NOTICE 'D-whatsapp tests passed (old accounts without whatsapp: %)', v_n;
END;
$test$;
ROLLBACK;
