-- =========================================================
-- WASLA - Record: public.admin_remove_staff(uuid)
--
-- RECORD OF AN ALREADY-APPLIED LIVE CHANGE. Do not treat as new behavior.
-- On 2026-11-27 the owner directed that public.admin_remove_staff be changed
-- to SECURITY DEFINER (search_path = ''). The change was applied directly on
-- the live database, OUTSIDE migration tracking (no entry exists in
-- supabase_migrations.schema_migrations after 20261127120739).
-- This file records the live function text, verified verbatim from the live
-- database via pg_get_functiondef (owner dashboard SQL Editor, 2026-11-27),
-- and the live execute privileges (postgres, authenticated, service_role;
-- anon and PUBLIC cannot execute).
-- It is idempotent (CREATE OR REPLACE plus REVOKE/GRANT to the same state).
-- The previous function text is unknown and is not recorded here.
-- =========================================================

CREATE OR REPLACE FUNCTION public.admin_remove_staff(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_role text;
  v_status text;
BEGIN
  IF (SELECT auth.uid()) IS NULL
     OR NOT private.is_active_admin() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF p_user_id IS NULL
     OR p_user_id = (SELECT auth.uid()) THEN
    RAISE EXCEPTION 'Invalid staff account';
  END IF;

  SELECT role, status
  INTO v_role, v_status
  FROM public.profiles
  WHERE id = p_user_id
  FOR UPDATE;

  IF NOT FOUND OR v_role <> 'staff' THEN
    RAISE EXCEPTION 'Staff account not found';
  END IF;

  IF v_status = 'suspended' THEN
    RAISE EXCEPTION 'Staff account already suspended';
  END IF;

  IF v_status NOT IN ('active', 'pending') THEN
    RAISE EXCEPTION 'Invalid staff status';
  END IF;

  UPDATE public.staff_permissions
  SET is_active = false,
      updated_at = now()
  WHERE user_id = p_user_id;

  UPDATE public.profiles
  SET suspension_previous_status = v_status,
      status = 'suspended',
      updated_at = now()
  WHERE id = p_user_id;
END;
$function$
;

revoke all on function public.admin_remove_staff(uuid) from public;
revoke all on function public.admin_remove_staff(uuid) from anon;
grant execute on function public.admin_remove_staff(uuid) to authenticated;
grant execute on function public.admin_remove_staff(uuid) to service_role;
