-- Tests for 20261128_d3_staff_documents_and_suspension.sql. Everything is rolled back.
BEGIN;
DO $test$
DECLARE v_s uuid; v_admin uuid; v_owner uuid; v_ok boolean; v_st text; v_act boolean; v_n int;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','',true);
  IF has_function_privilege('anon','public.admin_suspend_staff(uuid,text)','EXECUTE')
     OR has_function_privilege('anon','public.admin_reactivate_staff(uuid,text)','EXECUTE') THEN RAISE EXCEPTION 'anon can execute'; END IF;
  IF has_table_privilege('anon','public.staff_documents','SELECT') THEN RAISE EXCEPTION 'anon can read staff_documents'; END IF;
  SELECT p.id INTO v_s FROM public.profiles p JOIN public.staff_permissions sp ON sp.user_id=p.id
   WHERE p.role='staff' AND p.status='active' AND sp.is_active ORDER BY p.created_at LIMIT 1;
  SELECT id INTO v_admin FROM public.profiles WHERE role='admin' AND status='active' LIMIT 1;
  SELECT id INTO v_owner FROM public.profiles WHERE role='owner' AND status='active' LIMIT 1;
  IF v_s IS NULL OR v_admin IS NULL OR v_owner IS NULL THEN RAISE EXCEPTION 'prereq'; END IF;

  -- staff cannot suspend
  PERFORM set_config('request.jwt.claim.sub',v_s::text,true);
  v_ok:=false; BEGIN PERFORM public.admin_suspend_staff(v_s,'valid reason'); EXCEPTION WHEN SQLSTATE '42501' THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'staff could suspend'; END IF;

  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  v_ok:=false; BEGIN PERFORM public.admin_suspend_staff(v_s,'abc'); EXCEPTION WHEN OTHERS THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'short reason accepted'; END IF;
  v_ok:=false; BEGIN PERFORM public.admin_suspend_staff(v_owner,'valid reason'); EXCEPTION WHEN OTHERS THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'owner could be suspended'; END IF;
  v_ok:=false; BEGIN PERFORM public.admin_suspend_staff(v_admin,'valid reason'); EXCEPTION WHEN OTHERS THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'admin could suspend self'; END IF;

  PERFORM public.admin_suspend_staff(v_s,'اختبار الإيقاف');
  SELECT status INTO v_st FROM public.profiles WHERE id=v_s;
  SELECT is_active INTO v_act FROM public.staff_permissions WHERE user_id=v_s;
  IF v_st<>'suspended' OR v_act THEN RAISE EXCEPTION 'suspend did not take effect'; END IF;
  v_ok:=false; BEGIN PERFORM public.admin_suspend_staff(v_s,'valid reason'); EXCEPTION WHEN OTHERS THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'double suspend accepted'; END IF;
  v_ok:=false; BEGIN PERFORM public.admin_reactivate_staff(v_s,'x'); EXCEPTION WHEN OTHERS THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'reactivate without reason accepted'; END IF;
  PERFORM public.admin_reactivate_staff(v_s,'اختبار إعادة التفعيل');
  SELECT status INTO v_st FROM public.profiles WHERE id=v_s;
  SELECT is_active INTO v_act FROM public.staff_permissions WHERE user_id=v_s;
  IF v_st<>'active' OR NOT v_act THEN RAISE EXCEPTION 'reactivate did not restore'; END IF;

  -- documents: admin can insert/read, staff cannot see
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  SET LOCAL ROLE authenticated;
  INSERT INTO public.staff_documents(user_id,doc_type,file_path,file_name,mime_type,size_bytes,uploaded_by)
  VALUES (v_s,'contract',v_s::text||'/c.pdf','c.pdf','application/pdf',100,v_admin);
  SELECT count(*) INTO v_n FROM public.staff_documents WHERE user_id=v_s;
  IF v_n<>1 THEN RAISE EXCEPTION 'admin cannot read own insert'; END IF;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub',v_s::text,true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_n FROM public.staff_documents;
  IF v_n<>0 THEN RAISE EXCEPTION 'staff can read staff documents'; END IF;
  v_ok:=false;
  BEGIN INSERT INTO public.staff_documents(user_id,file_path,file_name,uploaded_by) VALUES (v_s,'x','x',v_s);
  EXCEPTION WHEN OTHERS THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'staff could insert a document'; END IF;
  RESET ROLE;
  RAISE NOTICE 'D-staff tests passed';
END;
$test$;
ROLLBACK;
