-- Tests for 20261128_d4_staff_reports.sql. Everything is rolled back.
BEGIN;
DO $test$
DECLARE v_s uuid; v_admin uuid; v_owner uuid; v_res jsonb; v_ok boolean; v_orig text[];
BEGIN
  PERFORM set_config('request.jwt.claim.sub','',true);
  IF has_function_privilege('anon','public.staff_reports_summary(date,date)','EXECUTE') THEN RAISE EXCEPTION 'anon can execute'; END IF;
  SELECT p.id INTO v_s FROM public.profiles p JOIN public.staff_permissions sp ON sp.user_id=p.id WHERE p.role='staff' AND p.status='active' AND sp.is_active ORDER BY p.created_at LIMIT 1;
  SELECT id INTO v_admin FROM public.profiles WHERE role='admin' AND status='active' LIMIT 1;
  SELECT id INTO v_owner FROM public.profiles WHERE role='owner' AND status='active' LIMIT 1;
  IF v_s IS NULL OR v_admin IS NULL OR v_owner IS NULL THEN RAISE EXCEPTION 'prereq'; END IF;
  -- staff without reports.view
  UPDATE public.staff_permissions SET permissions=ARRAY['dashboard.view'], is_active=true WHERE user_id=v_s;
  PERFORM set_config('request.jwt.claim.sub',v_s::text,true);
  v_ok:=false; BEGIN PERFORM public.staff_reports_summary(current_date-30,current_date); EXCEPTION WHEN SQLSTATE '42501' THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'staff without reports.view allowed'; END IF;
  -- reports.view without payments.view: financial null
  PERFORM set_config('request.jwt.claim.sub','',true);
  UPDATE public.staff_permissions SET permissions=ARRAY['reports.view'] WHERE user_id=v_s;
  PERFORM set_config('request.jwt.claim.sub',v_s::text,true);
  v_res := public.staff_reports_summary(current_date-365,current_date);
  IF v_res->'financial' IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'financial leaked'; END IF;
  IF v_res::text ~* '(phone|whatsapp|email)' THEN RAISE EXCEPTION 'contact key in output'; END IF;
  -- range too large
  v_ok:=false; BEGIN PERFORM public.staff_reports_summary(current_date-400,current_date); EXCEPTION WHEN SQLSTATE '22023' THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'long range accepted'; END IF;
  -- admin and owner see financial
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  v_res := public.staff_reports_summary(current_date-365,current_date);
  IF jsonb_typeof(v_res->'financial')<>'object' THEN RAISE EXCEPTION 'admin no financial'; END IF;
  PERFORM set_config('request.jwt.claim.sub',v_owner::text,true);
  v_res := public.staff_reports_summary(current_date-365,current_date);
  IF jsonb_typeof(v_res->'financial')<>'object' THEN RAISE EXCEPTION 'owner no financial'; END IF;
  RAISE NOTICE 'E tests passed';
END;
$test$;
ROLLBACK;
