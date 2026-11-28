BEGIN;

DO $test$
DECLARE
  -- Test identities
  v_staff_id uuid;
  v_admin_id uuid;
  v_owner_id uuid;
  v_customer public.profiles%ROWTYPE;
  v_missing_id uuid := '00000000-0000-0000-0000-000000000001';

  -- Original state for rollback
  v_original_permissions text[];

  -- Function results
  v_list jsonb;
  v_detail jsonb;
  v_item jsonb;
  v_requests jsonb;
  v_pattern text;

  -- Counts
  v_list_count integer;
  v_wildcard_count integer;
  v_phone_search_count integer;

  v_profiles_before bigint;
  v_requests_before bigint;
  v_staff_permissions_before bigint;
  v_audit_before bigint;
  v_grants_before bigint;

  -- Flags
  v_found_customer boolean;
  v_expected_rejection boolean;
  v_has_whatsapp boolean;

  -- Test role
  v_role_code text := 'ASV';

BEGIN
  ----------------------------------------------------------------
  -- 0) Snapshot counts before testing
  ----------------------------------------------------------------
  SELECT count(*) INTO v_profiles_before
  FROM public.profiles;

  SELECT count(*) INTO v_requests_before
  FROM public.service_requests;

  SELECT count(*) INTO v_staff_permissions_before
  FROM public.staff_permissions;

  SELECT count(*) INTO v_audit_before
  FROM public.audit_logs;

  SELECT count(*) INTO v_grants_before
  FROM private.staff_permission_grants;

  ----------------------------------------------------------------
  -- 1) Select a real active ASV employee without customers permissions
  ----------------------------------------------------------------
  SELECT p.id, sp.permissions
  INTO v_staff_id, v_original_permissions
  FROM public.profiles p
  JOIN public.staff_permissions sp
    ON sp.user_id = p.id
  WHERE p.role = 'staff'
    AND p.staff_role_code = v_role_code
    AND p.status = 'active'
    AND sp.is_active = true
    AND NOT (
      'customers.view' = ANY(coalesce(sp.permissions, '{}'::text[]))
      OR 'customers.manage' = ANY(coalesce(sp.permissions, '{}'::text[]))
      OR 'customers.contact' = ANY(coalesce(sp.permissions, '{}'::text[]))
    )
  ORDER BY cardinality(coalesce(sp.permissions, '{}'::text[]))
  LIMIT 1;

  IF v_staff_id IS NULL THEN
    RAISE EXCEPTION
      'No eligible active ASV employee without customers permissions';
  END IF;

  ----------------------------------------------------------------
  -- 2) Select a real customer with phone data
  ----------------------------------------------------------------
  SELECT *
  INTO v_customer
  FROM public.profiles
  WHERE role = 'customer'
    AND phone IS NOT NULL
    AND btrim(phone) <> ''
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_customer.id IS NULL THEN
    RAISE EXCEPTION
      'No customer with a real phone number available for tests';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name = 'whatsapp_number'
  )
  INTO v_has_whatsapp;

  ----------------------------------------------------------------
  -- 3) ACL checks
--    These assume the functions and ACL have already been applied.
  ----------------------------------------------------------------
  IF NOT has_function_privilege(
    'authenticated',
    'public.staff_list_customers(text,integer,integer)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION
      'authenticated lacks EXECUTE on staff_list_customers';
  END IF;

  IF NOT has_function_privilege(
    'authenticated',
    'public.staff_get_customer(uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION
      'authenticated lacks EXECUTE on staff_get_customer';
  END IF;

  IF has_function_privilege(
    'anon',
    'public.staff_list_customers(text,integer,integer)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION
      'anon unexpectedly has EXECUTE on staff_list_customers';
  END IF;

  IF has_function_privilege(
    'anon',
    'public.staff_get_customer(uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION
      'anon unexpectedly has EXECUTE on staff_get_customer';
  END IF;

  ----------------------------------------------------------------
  -- 4) Unauthenticated rejection for both functions
  ----------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', '', true);

  v_expected_rejection := false;

  BEGIN
    PERFORM public.staff_list_customers(NULL, 50, 0);
  EXCEPTION
    WHEN SQLSTATE '42501' THEN
      v_expected_rejection := true;
  END;

  IF NOT v_expected_rejection THEN
    RAISE EXCEPTION
      'Unauthenticated list call was not rejected with 42501';
  END IF;

  v_expected_rejection := false;

  BEGIN
    PERFORM public.staff_get_customer(v_customer.id);
  EXCEPTION
    WHEN SQLSTATE '42501' THEN
      v_expected_rejection := true;
  END;

  IF NOT v_expected_rejection THEN
    RAISE EXCEPTION
      'Unauthenticated detail call was not rejected with 42501';
  END IF;

  ----------------------------------------------------------------
  -- 5) Staff with NO customers permissions is denied
  ----------------------------------------------------------------
  PERFORM set_config(
    'request.jwt.claim.sub',
    v_staff_id::text,
    true
  );

  v_expected_rejection := false;

  BEGIN
    PERFORM public.staff_list_customers(NULL, 50, 0);
  EXCEPTION
    WHEN SQLSTATE '42501' THEN
      v_expected_rejection := true;
  END;

  IF NOT v_expected_rejection THEN
    RAISE EXCEPTION
      'Staff without customers permissions was not rejected';
  END IF;

  v_expected_rejection := false;

  BEGIN
    PERFORM public.staff_get_customer(v_customer.id);
  EXCEPTION
    WHEN SQLSTATE '42501' THEN
      v_expected_rejection := true;
  END;

  IF NOT v_expected_rejection THEN
    RAISE EXCEPTION
      'Staff without customers permissions was not rejected by detail';
  END IF;

  ----------------------------------------------------------------
  -- 6) Temporarily grant customers.view only
  ----------------------------------------------------------------
  UPDATE public.staff_permissions
  SET permissions = array_append(
    coalesce(v_original_permissions, '{}'::text[]),
    'customers.view'
  )
  WHERE user_id = v_staff_id;

  ----------------------------------------------------------------
  -- 7) List test with view only
  ----------------------------------------------------------------
  v_list := public.staff_list_customers(NULL, 100, 0);
  v_list_count := jsonb_array_length(v_list);

  IF v_list_count = 0 THEN
    RAISE EXCEPTION
      'Customer list returned no customers';
  END IF;

  ----------------------------------------------------------------
  -- 8) List contact fields must be hidden without contact permission
  ----------------------------------------------------------------
  FOR v_item IN
    SELECT value
    FROM jsonb_array_elements(v_list)
  LOOP
    IF v_item->>'phone' IS NOT NULL THEN
      RAISE EXCEPTION
        'phone leaked from list without customers.contact';
    END IF;

    IF v_item->>'whatsapp_number' IS NOT NULL THEN
      RAISE EXCEPTION
        'whatsapp_number leaked from list without customers.contact';
    END IF;
  END LOOP;
----------------------------------------------------------------
  -- 9) Wildcard / special-character search tests
  --    %, escaped underscore, backslash, and underscore alone
  ----------------------------------------------------------------
  FOREACH v_pattern IN ARRAY ARRAY[
    '%',
    chr(92) || '_',
    chr(92),
    '_'
  ]
  LOOP
    v_list := public.staff_list_customers(v_pattern, 100, 0);
    v_wildcard_count := jsonb_array_length(v_list);

    IF v_wildcard_count >= v_list_count THEN
      RAISE EXCEPTION
        'Wildcard/special-character search returned all customers';
    END IF;
  END LOOP;

  ----------------------------------------------------------------
  -- 10) Searching by a real phone must not return results
  ----------------------------------------------------------------
  v_list := public.staff_list_customers(v_customer.phone, 100, 0);
  v_phone_search_count := jsonb_array_length(v_list);

  IF v_phone_search_count <> 0 THEN
    RAISE EXCEPTION
      'Phone search returned results; contact data may be searchable';
  END IF;

  ----------------------------------------------------------------
  -- 11) Pagination boundaries
  ----------------------------------------------------------------
  v_expected_rejection := false;

  BEGIN
    PERFORM public.staff_list_customers(NULL, 0, 0);
  EXCEPTION
    WHEN SQLSTATE '22023' THEN
      v_expected_rejection := true;
  END;

  IF NOT v_expected_rejection THEN
    RAISE EXCEPTION
      'limit=0 was not rejected';
  END IF;

  v_expected_rejection := false;

  BEGIN
    PERFORM public.staff_list_customers(NULL, 101, 0);
  EXCEPTION
    WHEN SQLSTATE '22023' THEN
      v_expected_rejection := true;
  END;

  IF NOT v_expected_rejection THEN
    RAISE EXCEPTION
      'limit=101 was not rejected';
  END IF;

  v_expected_rejection := false;

  BEGIN
    PERFORM public.staff_list_customers(NULL, 50, -1);
  EXCEPTION
    WHEN SQLSTATE '22023' THEN
      v_expected_rejection := true;
  END;

  IF NOT v_expected_rejection THEN
    RAISE EXCEPTION
      'negative offset was not rejected';
  END IF;

  ----------------------------------------------------------------
  -- 12) Customer detail with view only
  ----------------------------------------------------------------
  v_detail := public.staff_get_customer(v_customer.id);

  IF v_detail IS NULL THEN
    RAISE EXCEPTION
      'Customer detail unexpectedly returned NULL';
  END IF;

  IF v_detail->>'phone' IS NOT NULL THEN
    RAISE EXCEPTION
      'phone leaked from detail without customers.contact';
  END IF;

  IF v_detail->>'whatsapp_number' IS NOT NULL THEN
    RAISE EXCEPTION
      'whatsapp_number leaked from detail without customers.contact';
  END IF;

  IF v_detail->>'address' IS NOT NULL THEN
    RAISE EXCEPTION
      'address leaked from detail without customers.contact';
  END IF;

  IF v_detail ? 'request_number' THEN
    RAISE EXCEPTION
      'request_number should not exist in customer detail';
  END IF;

  v_requests := coalesce(v_detail->'requests', '[]'::jsonb);

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(v_requests) r
    WHERE r.value ? 'request_number'
  ) THEN
    RAISE EXCEPTION
      'request_number found inside request records';
  END IF;

  ----------------------------------------------------------------
  -- 13) suspension_reason shape
  ----------------------------------------------------------------
  IF v_customer.status = 'suspended' THEN
    IF v_detail->>'suspension_reason'
       IS DISTINCT FROM v_customer.suspension_reason THEN
      RAISE EXCEPTION
        'suspension_reason did not match customer profile';
    END IF;
  ELSE
    IF v_detail->>'suspension_reason' IS NOT NULL THEN
      RAISE EXCEPTION
        'suspension_reason returned for non-suspended customer';
    END IF;
  END IF;

  ----------------------------------------------------------------
  -- 14) Nonexistent customer: verify P0001 + exact message
  ----------------------------------------------------------------
  v_expected_rejection := false;

  BEGIN
    PERFORM public.staff_get_customer(v_missing_id);
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM <> 'Customer not found' THEN
        RAISE EXCEPTION
          'Unexpected exception message for missing customer: %',
          SQLERRM;
      END IF;

      v_expected_rejection := true;
  END;

  IF NOT v_expected_rejection THEN
    RAISE EXCEPTION
      'Missing customer did not raise Customer not found';
  END IF;

  ----------------------------------------------------------------
  -- 15) Temporarily add customers.contact
  ----------------------------------------------------------------
  UPDATE public.staff_permissions
  SET permissions = array_append(
    coalesce(permissions, '{}'::text[]),
    'customers.contact'
  )
  WHERE user_id = v_staff_id;

  ----------------------------------------------------------------
  -- 16) List fields visible with contact
  ----------------------------------------------------------------
  v_list := public.staff_list_customers(NULL, 100, 0);
  v_found_customer := false;

  FOR v_item IN
    SELECT value
    FROM jsonb_array_elements(v_list)
  LOOP
    IF v_item->>'id' = v_customer.id::text THEN
      v_found_customer := true;

      IF v_item->>'phone'
         IS DISTINCT FROM v_customer.phone THEN
        RAISE EXCEPTION
          'List phone not visible/matching with contact permission';
      END IF;

      IF v_item->>'address' IS NOT NULL THEN
        RAISE EXCEPTION
          'List unexpectedly includes address field (not part of list schema)';
      END IF;

      IF v_has_whatsapp THEN
        IF v_item->>'whatsapp_number' IS NULL THEN
          RAISE EXCEPTION
            'WhatsApp should be visible in list if column exists';
        END IF;
      ELSE
        IF v_item->>'whatsapp_number' IS NOT NULL THEN
          RAISE EXCEPTION
            'WhatsApp should remain NULL because column is absent';
        END IF;
      END IF;
    END IF;
  END LOOP;

  IF NOT v_found_customer THEN
    RAISE EXCEPTION
      'Test customer was not found in contact-enabled list';
  END IF;

  ----------------------------------------------------------------
  -- 17) Detail contact fields visible with contact permission
  ----------------------------------------------------------------
  v_detail := public.staff_get_customer(v_customer.id);

  IF v_detail->>'phone' IS DISTINCT FROM v_customer.phone THEN
    RAISE EXCEPTION
      'Detail phone not visible/matching with contact permission';
  END IF;

  IF v_detail->>'address'
     IS DISTINCT FROM v_customer.address THEN
    RAISE EXCEPTION
      'Detail address not visible/matching with contact permission';
  END IF;

  IF v_has_whatsapp THEN
    IF v_detail->>'whatsapp_number' IS NULL THEN
      RAISE EXCEPTION
        'Detail WhatsApp should be visible if column exists';
    END IF;
  ELSE
    IF v_detail->>'whatsapp_number' IS NOT NULL THEN
      RAISE EXCEPTION
        'WhatsApp should remain NULL because column is absent';
    END IF;
  END IF;

  ----------------------------------------------------------------
  -- 18) Active admin access without customers.view (mandatory)
  ----------------------------------------------------------------
  SELECT id
  INTO v_admin_id
  FROM public.profiles
  WHERE role = 'admin'
    AND status = 'active'
  ORDER BY created_at
  LIMIT 1;

  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION
      'Security test failed: no active admin identity available';
  END IF;

  PERFORM set_config(
    'request.jwt.claim.sub',
    v_admin_id::text,
    true
  );

  IF NOT private.is_active_admin() THEN
    RAISE EXCEPTION
      'Selected admin identity does not satisfy private.is_active_admin()';
  END IF;

  v_list := public.staff_list_customers(NULL, 100, 0);

  IF jsonb_array_length(v_list) = 0 THEN
    RAISE EXCEPTION
      'Active admin could not list customers without customers.view';
  END IF;

  v_detail := public.staff_get_customer(v_customer.id);

  IF v_detail->>'phone' IS DISTINCT FROM v_customer.phone THEN
    RAISE EXCEPTION 'Admin contact phone not visible';
  END IF;

  IF v_detail->>'address' IS DISTINCT FROM v_customer.address THEN
    RAISE EXCEPTION 'Admin contact address not visible';
  END IF;

  RAISE NOTICE 'Admin security test passed for identity: %', v_admin_id;

  ----------------------------------------------------------------
  -- 19) Active owner access without customers.view (mandatory)
  ----------------------------------------------------------------
  SELECT id
  INTO v_owner_id
  FROM public.profiles
  WHERE role = 'owner'
    AND status = 'active'
  ORDER BY created_at
  LIMIT 1;

  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION
      'Security test failed: no active owner identity available';
  END IF;

  PERFORM set_config(
    'request.jwt.claim.sub',
    v_owner_id::text,
    true
  );

  IF NOT private.is_active_admin() THEN
    RAISE EXCEPTION
      'Selected owner identity does not satisfy private.is_active_admin()';
  END IF;

  v_list := public.staff_list_customers(NULL, 100, 0);

  IF jsonb_array_length(v_list) = 0 THEN
    RAISE EXCEPTION
      'Active owner could not list customers without customers.view';
  END IF;

  v_detail := public.staff_get_customer(v_customer.id);

  IF v_detail->>'phone' IS DISTINCT FROM v_customer.phone THEN
    RAISE EXCEPTION 'Owner contact phone not visible';
  END IF;

  IF v_detail->>'address' IS DISTINCT FROM v_customer.address THEN
    RAISE EXCEPTION 'Owner contact address not visible';
  END IF;

  RAISE NOTICE 'Owner security test passed for identity: %', v_owner_id;

  ----------------------------------------------------------------
  -- 20) Report test summary (no PII)
  ----------------------------------------------------------------
  RAISE NOTICE
    'C1 TESTS PASSED: test_role=%, list_count=%, phone_search_count=%, whatsapp_column_exists=%',
    v_role_code,
    v_list_count,
    v_phone_search_count,
    v_has_whatsapp;

  RAISE NOTICE
    'Before test counts: profiles=%, service_requests=%, staff_permissions=%, audit_logs=%, staff_permission_grants=%',
    v_profiles_before,
    v_requests_before,
    v_staff_permissions_before,
    v_audit_before,
    v_grants_before;

END;
$test$;

ROLLBACK;
