-- C2: customer reactivation + internal notes (staff).
-- Part 1: table customer_notes (locked, function-only access)
-- Part 2: prevent_profile_privilege_change: ONE added branch (customer reactivation by the C2 function only)
-- Part 3: staff_set_customer_status (reactivation only)
-- Part 4: staff_add_customer_note + staff_list_customer_notes
-- Part 5: ACL

-- ===== Part 1 =====
CREATE TABLE IF NOT EXISTS public.customer_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  author_id uuid NOT NULL REFERENCES public.profiles(id),
  note text NOT NULL CHECK (length(btrim(note)) BETWEEN 5 AND 1000),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS customer_notes_customer_idx
  ON public.customer_notes (customer_id, created_at DESC);

ALTER TABLE public.customer_notes ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.customer_notes FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS audit_row_change ON public.customer_notes;
CREATE TRIGGER audit_row_change
  AFTER INSERT OR UPDATE OR DELETE ON public.customer_notes
  FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();

-- ===== Part 2 (protected function: existing body kept, one branch added) =====
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

  if v_uid = old.id then
    raise exception 'You cannot change your own role or status';
  end if;

  if not private.is_active_admin() then
    raise exception 'Only active administrators can change account privileges';
  end if;

  return new;
end;
$function$;

-- ===== Part 3 =====
CREATE OR REPLACE FUNCTION public.staff_set_customer_status(
  p_customer_id uuid,
  p_status text,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid := (SELECT auth.uid());
  v_previous text;
  v_reason text := btrim(coalesce(p_reason, ''));
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required'
      USING ERRCODE = '42501';
  END IF;

  IF NOT (
    private.is_active_admin()
    OR private.has_permission('customers.manage')
  ) THEN
    RAISE EXCEPTION 'Not authorized'
      USING ERRCODE = '42501';
  END IF;

  IF p_customer_id IS NULL THEN
    RAISE EXCEPTION 'Customer id is required';
  END IF;

  IF p_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Only reactivation (active) is supported';
  END IF;

  IF length(v_reason) NOT BETWEEN 5 AND 500 THEN
    RAISE EXCEPTION 'Reason must be between 5 and 500 characters';
  END IF;

  SELECT p.suspension_previous_status
  INTO v_previous
  FROM public.profiles p
  WHERE p.id = p_customer_id
    AND p.role = 'customer'
    AND p.status = 'suspended'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Customer account is not suspended';
  END IF;

  IF v_previous IS NULL OR v_previous NOT IN ('active', 'pending') THEN
    RAISE EXCEPTION 'Previous customer account status is missing or invalid';
  END IF;

  PERFORM set_config('wasla.customer_reactivation', 'on', true);

  UPDATE public.profiles
  SET status = v_previous,
      suspension_previous_status = NULL,
      suspension_lift_reason = v_reason,
      suspension_lifted_at = now(),
      suspension_lifted_by = v_actor,
      updated_at = now()
  WHERE id = p_customer_id
    AND role = 'customer'
    AND status = 'suspended';

  IF NOT FOUND THEN
    PERFORM set_config('wasla.customer_reactivation', 'off', true);
    RAISE EXCEPTION 'Customer reactivation failed';
  END IF;

  PERFORM set_config('wasla.customer_reactivation', 'off', true);

  RETURN jsonb_build_object('id', p_customer_id, 'status', v_previous);
END;
$function$;

-- ===== Part 4 =====
CREATE OR REPLACE FUNCTION public.staff_add_customer_note(
  p_customer_id uuid,
  p_note text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid := (SELECT auth.uid());
  v_note text := btrim(coalesce(p_note, ''));
  v_id uuid;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required'
      USING ERRCODE = '42501';
  END IF;

  IF NOT (
    private.is_active_admin()
    OR private.has_permission('customers.manage')
  ) THEN
    RAISE EXCEPTION 'Not authorized'
      USING ERRCODE = '42501';
  END IF;

  IF length(v_note) NOT BETWEEN 5 AND 1000 THEN
    RAISE EXCEPTION 'Note must be between 5 and 1000 characters';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = p_customer_id AND p.role = 'customer'
  ) THEN
    RAISE EXCEPTION 'Customer not found';
  END IF;

  INSERT INTO public.customer_notes (customer_id, author_id, note)
  VALUES (p_customer_id, v_actor, v_note)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('id', v_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.staff_list_customer_notes(
  p_customer_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid := (SELECT auth.uid());
  v_result jsonb;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required'
      USING ERRCODE = '42501';
  END IF;

  IF NOT (
    private.is_active_admin()
    OR private.has_permission('customers.view')
    OR private.has_permission('customers.manage')
  ) THEN
    RAISE EXCEPTION 'Not authorized'
      USING ERRCODE = '42501';
  END IF;

  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', n.id,
        'note', n.note,
        'created_at', n.created_at,
        'author_name', a.full_name
      )
      ORDER BY n.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_result
  FROM public.customer_notes n
  LEFT JOIN public.profiles a ON a.id = n.author_id
  WHERE n.customer_id = p_customer_id;

  RETURN v_result;
END;
$function$;

-- ===== Part 5: ACL =====
REVOKE ALL ON FUNCTION
  public.staff_set_customer_status(uuid, text, text)
FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION
  public.staff_set_customer_status(uuid, text, text)
TO authenticated;

REVOKE ALL ON FUNCTION
  public.staff_add_customer_note(uuid, text)
FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION
  public.staff_add_customer_note(uuid, text)
TO authenticated;

REVOKE ALL ON FUNCTION
  public.staff_list_customer_notes(uuid)
FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION
  public.staff_list_customer_notes(uuid)
TO authenticated;
