BEGIN;
DO $test$
DECLARE v_hr uuid; v_target uuid; v_ok boolean; v_st text; v_prev_active boolean;
BEGIN
  SELECT id INTO v_hr FROM public.profiles WHERE role='staff' AND status='active' AND staff_role_code='FIN' LIMIT 1;
  SELECT id INTO v_target FROM public.profiles WHERE role='staff' AND status='active' AND staff_role_code='ASV' ORDER BY created_at LIMIT 1;
  IF v_hr IS NULL OR v_target IS NULL THEN RAISE EXCEPTION 'test fixtures missing'; END IF;
  -- caller without hr.manage is refused
  PERFORM set_config('request.jwt.claim.sub', v_hr::text, true);
  v_ok:=false;
  BEGIN PERFORM public.hr_suspend_staff(v_target,'no permission here'); EXCEPTION WHEN SQLSTATE '42501' THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'caller without hr.manage was allowed'; END IF;
  -- give hr.manage inside this rolled-back transaction
  UPDATE public.staff_permissions SET permissions = array_append(permissions,'hr.manage'), is_active = true WHERE user_id = v_hr;
  -- short reason refused
  v_ok:=false;
  BEGIN PERFORM public.hr_suspend_staff(v_target,'no'); EXCEPTION WHEN OTHERS THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'short reason accepted'; END IF;
  -- self refused
  v_ok:=false;
  BEGIN PERFORM public.hr_suspend_staff(v_hr,'suspend myself test'); EXCEPTION WHEN OTHERS THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'self suspend accepted'; END IF;
  -- suspend
  PERFORM public.hr_suspend_staff(v_target,'HR test suspension');
  SELECT status INTO v_st FROM public.profiles WHERE id=v_target;
  IF v_st <> 'suspended' THEN RAISE EXCEPTION 'not suspended'; END IF;
  IF EXISTS (SELECT 1 FROM public.staff_permissions WHERE user_id=v_target AND is_active) THEN RAISE EXCEPTION 'permissions still active'; END IF;
  v_ok:=false;
  BEGIN PERFORM public.hr_suspend_staff(v_target,'double suspend test'); EXCEPTION WHEN OTHERS THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'double suspend accepted'; END IF;
  -- reactivate
  PERFORM public.hr_reactivate_staff(v_target,'HR test reactivation');
  SELECT status INTO v_st FROM public.profiles WHERE id=v_target;
  IF v_st <> 'active' THEN RAISE EXCEPTION 'not reactivated'; END IF;
  -- direct status change by an HR caller (outside the functions) is still refused
  v_ok:=false;
  BEGIN UPDATE public.profiles SET status='suspended' WHERE id=v_target; EXCEPTION WHEN OTHERS THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'direct status update bypassed the trigger'; END IF;
  -- anon cannot execute
  IF has_function_privilege('anon','public.hr_suspend_staff(uuid,text)','EXECUTE') OR has_function_privilege('anon','public.hr_reactivate_staff(uuid,text)','EXECUTE') THEN RAISE EXCEPTION 'anon can execute'; END IF;
  RAISE NOTICE 'H3 tests passed';
END;
$test$;
ROLLBACK;
