-- Tests for d2a (run after d2a). Everything is rolled back.
BEGIN;
DO $test$
DECLARE v_c uuid; v_other uuid; v_other_wa text; v_ok boolean; v_wa text;
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
  RAISE NOTICE 'd2a tests passed';
END;
$test$;
ROLLBACK;
