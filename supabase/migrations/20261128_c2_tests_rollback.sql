-- C2 ROLLBACK tests. Run AFTER 20261128_c2_customer_actions.sql. Everything is rolled back.
BEGIN;

DO $test$
DECLARE
  v_staff_id uuid;
  v_orig_perms text[];
  v_admin_id uuid;
  v_owner_id uuid;
  v_customer_id uuid;
  v_other_id uuid;
  v_prof public.profiles%ROWTYPE;
  v_res jsonb;
  v_ok boolean;
  v_audit_before bigint;
  v_audit_after bigint;
  v_note_id uuid;
  v_list jsonb;
BEGIN
  -- 0) ACL / table lock
  IF has_function_privilege('anon', 'public.staff_set_customer_status(uuid,text,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.staff_add_customer_note(uuid,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.staff_list_customer_notes(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon can execute a C2 function';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.staff_set_customer_status(uuid,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.staff_add_customer_note(uuid,text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.staff_list_customer_notes(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated cannot execute a C2 function';
  END IF;
  IF has_table_privilege('authenticated', 'public.customer_notes', 'SELECT')
     OR has_table_privilege('authenticated', 'public.customer_notes', 'INSERT')
     OR has_table_privilege('anon', 'public.customer_notes', 'SELECT') THEN
    RAISE EXCEPTION 'customer_notes is not locked';
  END IF;

  -- fixtures (no jwt => auth.uid() is null)
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT p.id, sp.permissions INTO v_staff_id, v_orig_perms
  FROM public.profiles p
  JOIN public.staff_permissions sp ON sp.user_id = p.id
  WHERE p.role = 'staff' AND p.status = 'active' AND sp.is_active = true
    AND NOT ('customers.manage' = ANY(coalesce(sp.permissions, '{}'::text[])))
  ORDER BY cardinality(coalesce(sp.permissions, '{}'::text[]))
  LIMIT 1;
  IF v_staff_id IS NULL THEN
    RAISE EXCEPTION 'Test prerequisite missing: active staff without customers.manage';
  END IF;

  SELECT id INTO v_customer_id FROM public.profiles
  WHERE role = 'customer' AND status = 'active' ORDER BY created_at LIMIT 1;
  SELECT id INTO v_other_id FROM public.profiles
  WHERE role = 'customer' AND status = 'active' AND id <> v_customer_id ORDER BY created_at LIMIT 1;
  IF v_customer_id IS NULL OR v_other_id IS NULL THEN
    RAISE EXCEPTION 'Test prerequisite missing: two active customers';
  END IF;

  SELECT id INTO v_admin_id FROM public.profiles WHERE role = 'admin' AND status = 'active' ORDER BY created_at LIMIT 1;
  IF v_admin_id IS NULL THEN RAISE EXCEPTION 'Security test failed: no active admin identity available'; END IF;
  SELECT id INTO v_owner_id FROM public.profiles WHERE role = 'owner' AND status = 'active' ORDER BY created_at LIMIT 1;
  IF v_owner_id IS NULL THEN RAISE EXCEPTION 'Security test failed: no active owner identity available'; END IF;

  -- put one customer in suspended state (as the platform, auth.uid() null)
  UPDATE public.profiles
  SET status = 'suspended', suspension_previous_status = 'active',
      suspended_at = now(), suspension_reason = 'c2 test reason'
  WHERE id = v_customer_id;

  -- 1) staff WITHOUT customers.manage is rejected (status + note + notes list)
  PERFORM set_config('request.jwt.claim.sub', v_staff_id::text, true);
  v_ok := false;
  BEGIN
    PERFORM public.staff_set_customer_status(v_customer_id, 'active', 'valid reason here');
  EXCEPTION WHEN SQLSTATE '42501' THEN v_ok := true;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'Staff without customers.manage could reactivate'; END IF;

  v_ok := false;
  BEGIN
    PERFORM public.staff_add_customer_note(v_customer_id, 'valid note text');
  EXCEPTION WHEN SQLSTATE '42501' THEN v_ok := true;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'Staff without customers.manage could add a note'; END IF;

  v_ok := false;
  BEGIN
    PERFORM public.staff_list_customer_notes(v_customer_id);
  EXCEPTION WHEN SQLSTATE '42501' THEN v_ok := true;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'Staff without customers.view/manage could list notes'; END IF;

  -- 2) direct UPDATE of status by a non-admin staff must still fail (trigger not weakened)
  UPDATE public.staff_permissions
  SET permissions = array_append(coalesce(v_orig_perms, '{}'::text[]), 'customers.manage')
  WHERE user_id = v_staff_id;

  v_ok := false;
  BEGIN
    UPDATE public.profiles
    SET status = 'active', suspension_previous_status = NULL
    WHERE id = v_customer_id;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Only active administrators can change account privileges' THEN
      RAISE EXCEPTION 'Unexpected message for direct status update: %', SQLERRM;
    END IF;
    v_ok := true;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'Direct status update by staff was allowed'; END IF;

  -- 3) validation failures (staff now has customers.manage)
  v_ok := false;
  BEGIN
    PERFORM public.staff_set_customer_status(v_customer_id, 'active', 'abc');
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Reason must be between 5 and 500 characters' THEN RAISE EXCEPTION 'Unexpected message (short reason): %', SQLERRM; END IF;
    v_ok := true;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'Short reason was accepted'; END IF;

  v_ok := false;
  BEGIN
    PERFORM public.staff_set_customer_status(v_customer_id, 'suspended', 'valid reason here');
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Only reactivation (active) is supported' THEN RAISE EXCEPTION 'Unexpected message (status): %', SQLERRM; END IF;
    v_ok := true;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'Suspend via function was accepted'; END IF;

  v_ok := false;
  BEGIN
    PERFORM public.staff_set_customer_status(v_other_id, 'active', 'valid reason here');
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Customer account is not suspended' THEN RAISE EXCEPTION 'Unexpected message (not suspended): %', SQLERRM; END IF;
    v_ok := true;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'Reactivating a non-suspended customer was accepted'; END IF;

  v_ok := false;
  BEGIN
    PERFORM public.staff_set_customer_status(v_staff_id, 'active', 'valid reason here');
  EXCEPTION WHEN raise_exception THEN v_ok := true;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'Reactivating a non-customer id was accepted'; END IF;

  -- 4) successful reactivation by staff with customers.manage
  SELECT count(*) INTO v_audit_before FROM public.audit_logs;
  v_res := public.staff_set_customer_status(v_customer_id, 'active', '  تم حل المشكلة  ');
  SELECT count(*) INTO v_audit_after FROM public.audit_logs;

  SELECT * INTO v_prof FROM public.profiles WHERE id = v_customer_id;
  IF v_prof.status <> 'active' THEN RAISE EXCEPTION 'Customer not active after reactivation'; END IF;
  IF v_prof.suspension_previous_status IS NOT NULL THEN RAISE EXCEPTION 'previous status not cleared'; END IF;
  IF v_prof.suspension_lift_reason IS DISTINCT FROM 'تم حل المشكلة' THEN RAISE EXCEPTION 'lift reason not trimmed/stored'; END IF;
  IF v_prof.suspension_lifted_by IS DISTINCT FROM v_staff_id OR v_prof.suspension_lifted_at IS NULL THEN
    RAISE EXCEPTION 'lift metadata wrong';
  END IF;
  IF v_audit_after <= v_audit_before THEN RAISE EXCEPTION 'No audit row written for reactivation'; END IF;
  IF coalesce(current_setting('wasla.customer_reactivation', true), '') = 'on' THEN
    RAISE EXCEPTION 'reactivation flag leaked after function';
  END IF;
  IF v_res->>'status' <> 'active' THEN RAISE EXCEPTION 'unexpected function result'; END IF;

  -- 5) notes
  v_ok := false;
  BEGIN
    PERFORM public.staff_add_customer_note(v_customer_id, 'abc');
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Note must be between 5 and 1000 characters' THEN RAISE EXCEPTION 'Unexpected message (short note): %', SQLERRM; END IF;
    v_ok := true;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'Short note was accepted'; END IF;

  v_ok := false;
  BEGIN
    PERFORM public.staff_add_customer_note(v_staff_id, 'valid note text');
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Customer not found' THEN RAISE EXCEPTION 'Unexpected message (note non-customer): %', SQLERRM; END IF;
    v_ok := true;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'Note on non-customer was accepted'; END IF;

  v_res := public.staff_add_customer_note(v_customer_id, 'ملاحظة اختبار داخلية');
  v_note_id := (v_res->>'id')::uuid;
  v_list := public.staff_list_customer_notes(v_customer_id);
  IF jsonb_array_length(v_list) <> 1 OR (v_list->0->>'id')::uuid <> v_note_id THEN
    RAISE EXCEPTION 'Notes list does not return the new note';
  END IF;

  -- 6) admin (mandatory)
  UPDATE public.staff_permissions SET permissions = v_orig_perms WHERE user_id = v_staff_id;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  UPDATE public.profiles
  SET status = 'suspended', suspension_previous_status = 'active',
      suspension_lift_reason = NULL, suspension_lifted_at = NULL, suspension_lifted_by = NULL,
      suspended_at = now()
  WHERE id = v_customer_id;

  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  IF NOT private.is_active_admin() THEN RAISE EXCEPTION 'Selected admin identity does not satisfy private.is_active_admin()'; END IF;
  PERFORM public.staff_set_customer_status(v_customer_id, 'active', 'admin reactivation test');
  IF (SELECT status FROM public.profiles WHERE id = v_customer_id) <> 'active' THEN
    RAISE EXCEPTION 'Admin reactivation failed';
  END IF;
  PERFORM public.staff_add_customer_note(v_customer_id, 'admin note test');
  RAISE NOTICE 'Admin security test passed for identity: %', v_admin_id;

  -- 7) owner (mandatory)
  PERFORM set_config('request.jwt.claim.sub', '', true);
  UPDATE public.profiles
  SET status = 'suspended', suspension_previous_status = 'active',
      suspension_lift_reason = NULL, suspension_lifted_at = NULL, suspension_lifted_by = NULL,
      suspended_at = now()
  WHERE id = v_customer_id;

  PERFORM set_config('request.jwt.claim.sub', v_owner_id::text, true);
  IF NOT private.is_active_admin() THEN RAISE EXCEPTION 'Selected owner identity does not satisfy private.is_active_admin()'; END IF;
  PERFORM public.staff_set_customer_status(v_customer_id, 'active', 'owner reactivation test');
  IF (SELECT status FROM public.profiles WHERE id = v_customer_id) <> 'active' THEN
    RAISE EXCEPTION 'Owner reactivation failed';
  END IF;
  RAISE NOTICE 'Owner security test passed for identity: %', v_owner_id;

  RAISE NOTICE 'C2 tests passed: staff_id=%, customer_id=%', v_staff_id, v_customer_id;
END;
$test$;

ROLLBACK;
