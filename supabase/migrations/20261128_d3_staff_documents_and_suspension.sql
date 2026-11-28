-- D-staff: staff_documents table (admin/owner only through RLS) + admin_suspend_staff / admin_reactivate_staff.
-- The private storage bucket and its storage.objects policies are in a separate file
-- (20261128_d3s_staff_documents_storage.sql) because the postgres role here does not own storage.objects.
-- admin_remove_staff is not touched.
BEGIN;

CREATE TABLE IF NOT EXISTS public.staff_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  doc_type text NOT NULL DEFAULT 'contract' CHECK (doc_type IN ('contract','id','certificate','other')),
  file_path text NOT NULL,
  file_name text NOT NULL,
  mime_type text,
  size_bytes bigint,
  uploaded_by uuid REFERENCES public.profiles(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS staff_documents_user_idx ON public.staff_documents (user_id, created_at DESC);
ALTER TABLE public.staff_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS staff_documents_select ON public.staff_documents;
CREATE POLICY staff_documents_select ON public.staff_documents FOR SELECT TO authenticated
  USING (private.can_manage_staff_profile(user_id));
DROP POLICY IF EXISTS staff_documents_insert ON public.staff_documents;
CREATE POLICY staff_documents_insert ON public.staff_documents FOR INSERT TO authenticated
  WITH CHECK (private.can_manage_staff_profile(user_id) AND uploaded_by = (SELECT auth.uid()));
DROP POLICY IF EXISTS staff_documents_delete ON public.staff_documents;
CREATE POLICY staff_documents_delete ON public.staff_documents FOR DELETE TO authenticated
  USING (private.can_manage_staff_profile(user_id));

REVOKE ALL ON TABLE public.staff_documents FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, DELETE ON TABLE public.staff_documents TO authenticated;

DROP TRIGGER IF EXISTS audit_row_change ON public.staff_documents;
CREATE TRIGGER audit_row_change AFTER INSERT OR UPDATE OR DELETE ON public.staff_documents
  FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();

CREATE OR REPLACE FUNCTION public.admin_suspend_staff(p_user_id uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid := (SELECT auth.uid());
  v_status text;
  v_reason text := btrim(coalesce(p_reason, ''));
BEGIN
  IF v_actor IS NULL OR NOT private.is_active_admin() THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;
  IF p_user_id IS NULL OR p_user_id = v_actor THEN
    RAISE EXCEPTION 'Invalid staff account';
  END IF;
  IF length(v_reason) NOT BETWEEN 5 AND 500 THEN
    RAISE EXCEPTION 'Suspension reason must be between 5 and 500 characters';
  END IF;
  SELECT p.status INTO v_status FROM public.profiles p
  WHERE p.id = p_user_id AND p.role = 'staff' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Staff account not found'; END IF;
  IF v_status = 'suspended' THEN RAISE EXCEPTION 'Staff account already suspended'; END IF;
  IF v_status NOT IN ('active','pending') THEN RAISE EXCEPTION 'Invalid staff status'; END IF;

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

CREATE OR REPLACE FUNCTION public.admin_reactivate_staff(p_user_id uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid := (SELECT auth.uid());
  v_previous text;
  v_reason text := btrim(coalesce(p_reason, ''));
BEGIN
  IF v_actor IS NULL OR NOT private.is_active_admin() THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;
  IF p_user_id IS NULL OR p_user_id = v_actor THEN
    RAISE EXCEPTION 'Invalid staff account';
  END IF;
  IF length(v_reason) NOT BETWEEN 5 AND 500 THEN
    RAISE EXCEPTION 'Reactivation reason must be between 5 and 500 characters';
  END IF;
  SELECT p.suspension_previous_status INTO v_previous FROM public.profiles p
  WHERE p.id = p_user_id AND p.role = 'staff' AND p.status = 'suspended' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Staff account is not suspended'; END IF;
  IF v_previous IS NULL OR v_previous NOT IN ('active','pending') THEN
    RAISE EXCEPTION 'Previous staff status is missing or invalid';
  END IF;

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

REVOKE ALL ON FUNCTION public.admin_suspend_staff(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_suspend_staff(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_reactivate_staff(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_reactivate_staff(uuid, text) TO authenticated;

COMMIT;
