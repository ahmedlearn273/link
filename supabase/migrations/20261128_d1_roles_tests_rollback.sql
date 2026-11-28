-- Tests for 20261128_d1_roles_and_contact_assign.sql. Everything is rolled back.
BEGIN;
DO $test$
DECLARE v_s uuid; v_admin uuid; v_ok boolean; v_perm text[];
BEGIN
  PERFORM set_config('request.jwt.claim.sub','',true);
  SELECT id INTO v_s FROM public.profiles WHERE role='staff' AND status='active' AND staff_role_code IS NULL ORDER BY created_at LIMIT 1;
  IF v_s IS NULL THEN RAISE EXCEPTION 'prereq: staff without role code'; END IF;
  SELECT id INTO v_admin FROM public.profiles WHERE role='admin' AND status='active' LIMIT 1;
  IF v_admin IS NULL THEN RAISE EXCEPTION 'prereq: active admin'; END IF;
  UPDATE public.profiles SET staff_role_code='GM', staff_title='المدير العام' WHERE id=v_s;
  UPDATE public.profiles SET staff_role_code='HR', staff_title='الموارد البشرية' WHERE id=v_s;
  UPDATE public.profiles SET staff_role_code='ASV', staff_title='مشرف منطقة' WHERE id=v_s;
  v_ok:=false;
  BEGIN UPDATE public.profiles SET staff_role_code='GM', staff_title='اسم غلط' WHERE id=v_s;
  EXCEPTION WHEN check_violation THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'GM with wrong title was accepted'; END IF;
  v_ok:=false;
  BEGIN UPDATE public.profiles SET staff_role_code='HR', staff_title='خدمة العملاء' WHERE id=v_s;
  EXCEPTION WHEN check_violation THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'HR with wrong title was accepted'; END IF;
  -- admin can now give customers.contact, still cannot give reports.export
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  PERFORM public.admin_upsert_staff(v_s, ARRAY['dashboard.view','customers.view','customers.contact'], true);
  SELECT permissions INTO v_perm FROM public.staff_permissions WHERE user_id=v_s;
  IF NOT ('customers.contact' = ANY(v_perm)) THEN RAISE EXCEPTION 'customers.contact was not stored'; END IF;
  PERFORM public.admin_upsert_staff(v_s, ARRAY['providers.contact','hr.view'], true);
  v_ok:=false;
  BEGIN PERFORM public.admin_upsert_staff(v_s, ARRAY['reports.export'], true);
  EXCEPTION WHEN OTHERS THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'reports.export became assignable'; END IF;
  RAISE NOTICE 'D-roles tests passed';
END;
$test$;
ROLLBACK;
