-- H3/H4: HR portal staff suspend / reactivate. Mirrors admin_suspend_staff / admin_reactivate_staff,
-- but the caller needs the hr.manage permission (owner passes automatically).
-- HR cannot act on GM or HR accounts, and cannot act on itself.
BEGIN;

-- Protected trigger change: allow ONLY staff status moves between active/pending/suspended,
-- and ONLY from inside hr_suspend_staff / hr_reactivate_staff (local flag, owner postgres).
-- Everything else in the trigger is unchanged. Role changes are never allowed through this flag.
CREATE OR REPLACE FUNCTION public.prevent_profile_privilege_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    return new;
  end if;

  if new.role is not distinct from old.role
     and new.status is not distinct from old.status then
    return new;
  end if;

  -- C2: allow ONLY customer suspended -> active/pending, and ONLY from
  -- inside public.staff_set_customer_status (flag set locally, owner postgres).
  if coalesce(current_setting('wasla.customer_reactivation', true), '') = 'on'
     and current_user = 'postgres'
     and old.role = 'customer'
     and new.role = 'customer'
     and old.status = 'suspended'
     and new.status in ('active', 'pending') then
    return new;
  end if;

  -- H3: HR staff suspension / reactivation (flag set locally inside hr_* functions only).
  if coalesce(current_setting('wasla.hr_staff_status', true), '') = 'on'
     and current_user = 'postgres'
     and old.role = 'staff'
     and new.role = 'staff'
     and old.status in ('active', 'pending', 'suspended')
     and new.status in ('active', 'pending', 'suspended')
     and v_uid <> old.id then
    return new;
  end if;

  if v_uid = old.id then
    raise exception 'You cannot change your own role or status';
  end if;

  if not private.is_active_admin() then
    raise exception 'Only active administrators can change account privileges';
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.hr_suspend_staff(p_user_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid := (SELECT auth.uid());
  v_status text;
  v_code text;
  v_reason text := btrim(coalesce(p_reason, ''));
BEGIN
  IF v_actor IS NULL OR NOT private.has_permission('hr.manage') THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;
  IF p_user_id IS NULL OR p_user_id = v_actor THEN
    RAISE EXCEPTION 'Invalid staff account';
  END IF;
  IF length(v_reason) NOT BETWEEN 5 AND 500 THEN
    RAISE EXCEPTION 'Suspension reason must be between 5 and 500 characters';
  END IF;
  SELECT p.status, p.staff_role_code INTO v_status, v_code FROM public.profiles p
  WHERE p.id = p_user_id AND p.role = 'staff' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Staff account not found'; END IF;
  IF v_code IN ('GM','HR') AND NOT private.is_active_admin() THEN
    RAISE EXCEPTION 'Not authorized for this account' USING ERRCODE = '42501';
  END IF;
  IF v_status = 'suspended' THEN RAISE EXCEPTION 'Staff account already suspended'; END IF;
  IF v_status NOT IN ('active','pending') THEN RAISE EXCEPTION 'Invalid staff status'; END IF;

  PERFORM set_config('wasla.hr_staff_status','on',true);
  UPDATE public.staff_permissions SET is_active = false, updated_at = now() WHERE user_id = p_user_id;
  UPDATE public.profiles
  SET suspension_previous_status = v_status,
      status = 'suspended',
      suspension_reason = v_reason,
      suspended_at = now(),
      suspended_by = v_actor,
      suspension_lift_reason = NULL,
      suspension_lifted_at = NULL,
      suspension_lifted_by = NULL,
      updated_at = now()
  WHERE id = p_user_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.hr_reactivate_staff(p_user_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid := (SELECT auth.uid());
  v_previous text;
  v_code text;
  v_reason text := btrim(coalesce(p_reason, ''));
BEGIN
  IF v_actor IS NULL OR NOT private.has_permission('hr.manage') THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;
  IF p_user_id IS NULL OR p_user_id = v_actor THEN
    RAISE EXCEPTION 'Invalid staff account';
  END IF;
  IF length(v_reason) NOT BETWEEN 5 AND 500 THEN
    RAISE EXCEPTION 'Reactivation reason must be between 5 and 500 characters';
  END IF;
  SELECT p.suspension_previous_status, p.staff_role_code INTO v_previous, v_code FROM public.profiles p
  WHERE p.id = p_user_id AND p.role = 'staff' AND p.status = 'suspended' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Staff account is not suspended'; END IF;
  IF v_code IN ('GM','HR') AND NOT private.is_active_admin() THEN
    RAISE EXCEPTION 'Not authorized for this account' USING ERRCODE = '42501';
  END IF;
  IF v_previous IS NULL OR v_previous NOT IN ('active','pending') THEN
    RAISE EXCEPTION 'Previous staff status is missing or invalid';
  END IF;

  PERFORM set_config('wasla.hr_staff_status','on',true);
  UPDATE public.profiles
  SET status = v_previous,
      suspension_previous_status = NULL,
      suspension_lift_reason = v_reason,
      suspension_lifted_at = now(),
      suspension_lifted_by = v_actor,
      updated_at = now()
  WHERE id = p_user_id;
  UPDATE public.staff_permissions SET is_active = true, updated_at = now()
  WHERE user_id = p_user_id AND cardinality(coalesce(permissions, '{}'::text[])) > 0;
END;
$function$;

REVOKE ALL ON FUNCTION public.hr_suspend_staff(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.hr_reactivate_staff(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.hr_suspend_staff(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.hr_reactivate_staff(uuid, text) TO authenticated;

COMMIT;
