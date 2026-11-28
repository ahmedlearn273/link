-- Tests for d2b (run after d2a and d2b). Everything is rolled back.
BEGIN;
DO $test$
DECLARE v_ok boolean; v_new uuid := gen_random_uuid(); v_new2 uuid := gen_random_uuid(); v_wa text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','',true);
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
  RAISE NOTICE 'd2b tests passed';
END;
$test$;
ROLLBACK;
