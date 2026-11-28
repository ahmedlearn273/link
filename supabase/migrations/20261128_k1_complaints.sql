-- K1: complaints (new dedicated tables) + functions. Requires W1 (client wallet) first.
-- Compensation: wallet credit (platform funded) or one-time discount code (platform or provider funded).
-- Does NOT touch provider ratings. Does NOT create cron jobs or notifications.
BEGIN;

CREATE TABLE IF NOT EXISTS public.complaints (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.service_requests(id),
  customer_id uuid NOT NULL REFERENCES public.profiles(id),
  provider_id uuid REFERENCES public.provider_profiles(id),
  category text NOT NULL CHECK (category IN ('service_quality','provider_behavior','price_dispute','no_show','safety','platform','other')),
  description text NOT NULL CHECK (length(btrim(description)) BETWEEN 10 AND 1000),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_review','escalated','resolved','rejected')),
  assigned_to uuid REFERENCES public.profiles(id),
  escalation_level smallint NOT NULL DEFAULT 0 CHECK (escalation_level IN (0,1,2)),
  escalated_at timestamptz,
  resolution_note text CHECK (resolution_note IS NULL OR length(resolution_note) BETWEEN 5 AND 1000),
  compensation_type text NOT NULL DEFAULT 'none' CHECK (compensation_type IN ('none','discount_code','wallet_credit')),
  compensation_amount numeric(12,2) CHECK (compensation_amount IS NULL OR compensation_amount > 0),
  compensation_funded_by text CHECK (compensation_funded_by IS NULL OR compensation_funded_by IN ('platform','provider')),
  compensation_ref uuid,
  resolved_by uuid REFERENCES public.profiles(id),
  resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS complaints_one_open_per_request
  ON public.complaints (request_id) WHERE status IN ('open','in_review','escalated');
CREATE INDEX IF NOT EXISTS complaints_status_idx ON public.complaints (status, created_at DESC);
CREATE INDEX IF NOT EXISTS complaints_customer_idx ON public.complaints (customer_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.complaint_photos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  complaint_id uuid NOT NULL REFERENCES public.complaints(id) ON DELETE CASCADE,
  storage_path text NOT NULL CHECK (length(storage_path) BETWEEN 3 AND 300),
  uploaded_by uuid NOT NULL REFERENCES public.profiles(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS complaint_photos_complaint_idx ON public.complaint_photos (complaint_id);

CREATE TABLE IF NOT EXISTS public.complaint_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  complaint_id uuid NOT NULL REFERENCES public.complaints(id) ON DELETE CASCADE,
  actor_id uuid REFERENCES public.profiles(id),
  event_type text NOT NULL CHECK (event_type IN ('created','note','assigned','escalated','photo_added','resolved','rejected')),
  note text CHECK (note IS NULL OR length(note) <= 1000),
  meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS complaint_events_complaint_idx ON public.complaint_events (complaint_id, created_at);

ALTER TABLE public.complaints ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.complaint_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.complaint_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.complaints FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.complaint_photos FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.complaint_events FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS audit_row_change ON public.complaints;
CREATE TRIGGER audit_row_change AFTER INSERT OR UPDATE OR DELETE ON public.complaints
  FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
DROP TRIGGER IF EXISTS audit_row_change ON public.complaint_photos;
CREATE TRIGGER audit_row_change AFTER INSERT OR UPDATE OR DELETE ON public.complaint_photos
  FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
DROP TRIGGER IF EXISTS audit_row_change ON public.complaint_events;
CREATE TRIGGER audit_row_change AFTER INSERT OR UPDATE OR DELETE ON public.complaint_events
  FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();

-- ===== helpers (private, no API role) =====
-- Compensation limit per actor: owner/admin and GM uncapped, OPS 500, ASV 200, anyone else 0.
CREATE OR REPLACE FUNCTION private.complaint_comp_cap()
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT CASE
    WHEN private.is_active_admin() THEN 1000000000::numeric
    ELSE coalesce((
      SELECT CASE p.staff_role_code WHEN 'GM' THEN 1000000000::numeric WHEN 'OPS' THEN 500 WHEN 'ASV' THEN 200 ELSE 0 END
      FROM public.profiles p WHERE p.id = (SELECT auth.uid()) AND p.role = 'staff' AND p.status = 'active'
    ), 0)
  END;
$function$;

-- True when the caller may choose provider funding: owner/admin, GM, OPS.
CREATE OR REPLACE FUNCTION private.complaint_can_fund_by_provider()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT private.is_active_admin() OR EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = (SELECT auth.uid()) AND p.role = 'staff' AND p.status = 'active' AND p.staff_role_code IN ('GM','OPS'));
$function$;

REVOKE ALL ON FUNCTION private.complaint_comp_cap() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.complaint_can_fund_by_provider() FROM PUBLIC, anon, authenticated, service_role;

-- ===== customer side =====
CREATE OR REPLACE FUNCTION public.create_complaint(p_request_id uuid, p_category text, p_description text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_req public.service_requests%ROWTYPE;
  v_id uuid;
  v_desc text := btrim(coalesce(p_description, ''));
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND role = 'customer' AND status = 'active') THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;
  IF length(v_desc) NOT BETWEEN 10 AND 1000 THEN
    RAISE EXCEPTION 'Description must be between 10 and 1000 characters' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_req FROM public.service_requests WHERE id = p_request_id AND customer_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Request not found' USING ERRCODE = '22023'; END IF;
  IF v_req.provider_id IS NULL OR v_req.status NOT IN ('completed','cancelled') THEN
    RAISE EXCEPTION 'A complaint can be filed only for a completed or cancelled request that had a provider' USING ERRCODE = '22023';
  END IF;

  BEGIN
    INSERT INTO public.complaints (request_id, customer_id, provider_id, category, description)
    VALUES (v_req.id, v_uid, v_req.provider_id, p_category, v_desc)
    RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'There is already an open complaint for this request' USING ERRCODE = '22023';
  END;

  INSERT INTO public.complaint_events (complaint_id, actor_id, event_type, note)
  VALUES (v_id, v_uid, 'created', NULL);

  RETURN jsonb_build_object('id', v_id, 'status', 'open');
END;
$function$;

CREATE OR REPLACE FUNCTION public.add_complaint_photo(p_complaint_id uuid, p_storage_path text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_c public.complaints%ROWTYPE;
  v_id uuid;
  v_n integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_c FROM public.complaints WHERE id = p_complaint_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Complaint not found' USING ERRCODE = '22023'; END IF;
  IF NOT (v_c.customer_id = v_uid OR private.is_active_admin() OR private.has_permission('support.manage')) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;
  IF v_c.status IN ('resolved','rejected') THEN
    RAISE EXCEPTION 'Complaint is closed' USING ERRCODE = '22023';
  END IF;
  SELECT count(*) INTO v_n FROM public.complaint_photos WHERE complaint_id = p_complaint_id;
  IF v_n >= 5 THEN RAISE EXCEPTION 'Maximum 5 photos per complaint' USING ERRCODE = '22023'; END IF;

  INSERT INTO public.complaint_photos (complaint_id, storage_path, uploaded_by)
  VALUES (p_complaint_id, btrim(p_storage_path), v_uid) RETURNING id INTO v_id;
  INSERT INTO public.complaint_events (complaint_id, actor_id, event_type) VALUES (p_complaint_id, v_uid, 'photo_added');
  RETURN jsonb_build_object('id', v_id);
END;
$function$;

-- The customer sees status, the resolution text and the compensation they got.
-- Never the funding source, the staff identity, or internal notes.
CREATE OR REPLACE FUNCTION public.my_complaints()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'id', c.id, 'request_id', c.request_id, 'category', c.category, 'description', c.description,
      'status', CASE WHEN c.status = 'escalated' THEN 'in_review' ELSE c.status END,
      'resolution_note', c.resolution_note,
      'compensation_type', c.compensation_type, 'compensation_amount', c.compensation_amount,
      'compensation_code', CASE WHEN c.compensation_type = 'discount_code'
         THEN (SELECT pr.code FROM public.promotions pr WHERE pr.id = c.compensation_ref) END,
      'created_at', c.created_at, 'resolved_at', c.resolved_at
    ) ORDER BY c.created_at DESC)
    FROM public.complaints c WHERE c.customer_id = v_uid
  ), '[]'::jsonb);
END;
$function$;

-- ===== staff side =====
CREATE OR REPLACE FUNCTION public.staff_list_complaints(p_status text DEFAULT NULL, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  IF NOT (private.is_active_admin() OR private.has_permission('support.view') OR private.has_permission('support.manage')) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;
  IF p_status IS NOT NULL AND p_status NOT IN ('open','in_review','escalated','resolved','rejected') THEN
    RAISE EXCEPTION 'Invalid status' USING ERRCODE = '22023';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(row_to_json(t)::jsonb ORDER BY t.created_at DESC)
    FROM (
      SELECT c.id, c.request_id, c.category, c.status, c.escalation_level, c.assigned_to,
             c.compensation_type, c.compensation_amount, c.created_at, c.resolved_at,
             cu.full_name AS customer_name, pp.display_name AS provider_name,
             left(c.description, 140) AS summary
      FROM public.complaints c
      JOIN public.profiles cu ON cu.id = c.customer_id
      LEFT JOIN public.provider_profiles pp ON pp.id = c.provider_id
      WHERE p_status IS NULL OR c.status = p_status
      ORDER BY c.created_at DESC
      LIMIT least(greatest(coalesce(p_limit, 50), 1), 100) OFFSET greatest(coalesce(p_offset, 0), 0)
    ) t
  ), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.staff_get_complaint(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_c jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  IF NOT (private.is_active_admin() OR private.has_permission('support.view') OR private.has_permission('support.manage')) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;
  SELECT to_jsonb(c) || jsonb_build_object('customer_name', cu.full_name, 'provider_name', pp.display_name)
  INTO v_c
  FROM public.complaints c
  JOIN public.profiles cu ON cu.id = c.customer_id
  LEFT JOIN public.provider_profiles pp ON pp.id = c.provider_id
  WHERE c.id = p_id;
  IF v_c IS NULL THEN RAISE EXCEPTION 'Complaint not found' USING ERRCODE = '22023'; END IF;
  RETURN v_c || jsonb_build_object(
    'comp_cap', private.complaint_comp_cap(),
    'can_fund_by_provider', private.complaint_can_fund_by_provider(),
    'events', coalesce((SELECT jsonb_agg(jsonb_build_object('id', e.id, 'event_type', e.event_type, 'note', e.note,
                'actor_name', a.full_name, 'created_at', e.created_at) ORDER BY e.created_at)
               FROM public.complaint_events e LEFT JOIN public.profiles a ON a.id = e.actor_id WHERE e.complaint_id = p_id), '[]'::jsonb),
    'photos', coalesce((SELECT jsonb_agg(jsonb_build_object('id', ph.id, 'storage_path', ph.storage_path, 'created_at', ph.created_at)
               ORDER BY ph.created_at) FROM public.complaint_photos ph WHERE ph.complaint_id = p_id), '[]'::jsonb));
END;
$function$;

CREATE OR REPLACE FUNCTION public.staff_add_complaint_note(p_id uuid, p_note text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_note text := btrim(coalesce(p_note, ''));
  v_status text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  IF NOT (private.is_active_admin() OR private.has_permission('support.manage')) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;
  IF length(v_note) NOT BETWEEN 5 AND 1000 THEN
    RAISE EXCEPTION 'Note must be between 5 and 1000 characters' USING ERRCODE = '22023';
  END IF;
  SELECT status INTO v_status FROM public.complaints WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Complaint not found' USING ERRCODE = '22023'; END IF;
  IF v_status IN ('resolved','rejected') THEN RAISE EXCEPTION 'Complaint is closed' USING ERRCODE = '22023'; END IF;
  INSERT INTO public.complaint_events (complaint_id, actor_id, event_type, note) VALUES (p_id, v_uid, 'note', v_note);
  IF v_status = 'open' THEN
    UPDATE public.complaints SET status = 'in_review', updated_at = now() WHERE id = p_id;
  END IF;
  RETURN jsonb_build_object('id', p_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.staff_assign_complaint(p_id uuid, p_assignee uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_status text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  IF NOT (private.is_active_admin() OR private.has_permission('support.manage')) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_assignee AND role IN ('staff','admin','owner') AND status = 'active') THEN
    RAISE EXCEPTION 'Assignee must be an active staff member' USING ERRCODE = '22023';
  END IF;
  SELECT status INTO v_status FROM public.complaints WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Complaint not found' USING ERRCODE = '22023'; END IF;
  IF v_status IN ('resolved','rejected') THEN RAISE EXCEPTION 'Complaint is closed' USING ERRCODE = '22023'; END IF;
  UPDATE public.complaints
  SET assigned_to = p_assignee, status = CASE WHEN status = 'open' THEN 'in_review' ELSE status END, updated_at = now()
  WHERE id = p_id;
  INSERT INTO public.complaint_events (complaint_id, actor_id, event_type, meta)
  VALUES (p_id, v_uid, 'assigned', jsonb_build_object('assignee', p_assignee));
  RETURN jsonb_build_object('id', p_id, 'assigned_to', p_assignee);
END;
$function$;

CREATE OR REPLACE FUNCTION public.staff_reject_complaint(p_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_reason text := btrim(coalesce(p_reason, ''));
  v_status text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  IF NOT (private.is_active_admin() OR private.has_permission('support.manage')) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;
  IF length(v_reason) NOT BETWEEN 5 AND 1000 THEN
    RAISE EXCEPTION 'Reason must be between 5 and 1000 characters' USING ERRCODE = '22023';
  END IF;
  SELECT status INTO v_status FROM public.complaints WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Complaint not found' USING ERRCODE = '22023'; END IF;
  IF v_status IN ('resolved','rejected') THEN RAISE EXCEPTION 'Complaint is closed' USING ERRCODE = '22023'; END IF;
  UPDATE public.complaints
  SET status = 'rejected', resolution_note = v_reason, resolved_by = v_uid, resolved_at = now(), updated_at = now()
  WHERE id = p_id;
  INSERT INTO public.complaint_events (complaint_id, actor_id, event_type, note) VALUES (p_id, v_uid, 'rejected', v_reason);
  RETURN jsonb_build_object('id', p_id, 'status', 'rejected');
END;
$function$;

-- Resolve with optional compensation. Funding defaults to platform; only OPS/GM/admin/owner may pick provider.
CREATE OR REPLACE FUNCTION public.staff_resolve_complaint(
  p_id uuid, p_resolution text,
  p_comp_type text DEFAULT 'none', p_amount numeric DEFAULT NULL, p_funded_by text DEFAULT 'platform'
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_res text := btrim(coalesce(p_resolution, ''));
  v_c public.complaints%ROWTYPE;
  v_funded text := coalesce(p_funded_by, 'platform');
  v_ref uuid;
  v_code text;
  v_amount numeric(12,2);
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  IF NOT (private.is_active_admin() OR private.has_permission('support.manage')) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;
  IF length(v_res) NOT BETWEEN 5 AND 1000 THEN
    RAISE EXCEPTION 'Resolution must be between 5 and 1000 characters' USING ERRCODE = '22023';
  END IF;
  IF p_comp_type NOT IN ('none','discount_code','wallet_credit') THEN
    RAISE EXCEPTION 'Invalid compensation type' USING ERRCODE = '22023';
  END IF;
  IF v_funded NOT IN ('platform','provider') THEN
    RAISE EXCEPTION 'Invalid funding source' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_c FROM public.complaints WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Complaint not found' USING ERRCODE = '22023'; END IF;
  IF v_c.status IN ('resolved','rejected') THEN RAISE EXCEPTION 'Complaint is closed' USING ERRCODE = '22023'; END IF;

  IF p_comp_type = 'none' THEN
    v_amount := NULL; v_funded := NULL;
  ELSE
    IF p_amount IS NULL OR p_amount <= 0 THEN
      RAISE EXCEPTION 'Compensation amount must be positive' USING ERRCODE = '22023';
    END IF;
    v_amount := round(p_amount, 2);
    IF v_amount > private.complaint_comp_cap() THEN
      RAISE EXCEPTION 'Amount is above your compensation limit' USING ERRCODE = '42501';
    END IF;
    IF v_funded = 'provider' AND NOT private.complaint_can_fund_by_provider() THEN
      RAISE EXCEPTION 'Only operations, general manager or owner can choose provider funding' USING ERRCODE = '42501';
    END IF;
    IF p_comp_type = 'wallet_credit' AND v_funded <> 'platform' THEN
      RAISE EXCEPTION 'Wallet credit is platform funded only' USING ERRCODE = '22023';
    END IF;

    IF p_comp_type = 'wallet_credit' THEN
      PERFORM private.credit_customer_wallet(v_c.customer_id, v_amount, 'compensation',
        'تعويض عن شكوى', v_c.id, v_c.request_id, v_uid);
      v_ref := NULL;
    ELSE
      v_code := 'WSL' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
      INSERT INTO public.promotions
        (kind, code, title, description, discount_type, discount_value, usage_limit, per_user_limit,
         is_active, starts_at, ends_at, created_by, funded_by)
      VALUES ('code', v_code, 'تعويض عن شكوى', NULL, 'fixed', v_amount, 1, 1,
         true, now(), now() + interval '30 days', v_uid, v_funded)
      RETURNING id INTO v_ref;
    END IF;
  END IF;

  UPDATE public.complaints
  SET status = 'resolved', resolution_note = v_res, resolved_by = v_uid, resolved_at = now(), updated_at = now(),
      compensation_type = p_comp_type, compensation_amount = v_amount,
      compensation_funded_by = v_funded, compensation_ref = v_ref
  WHERE id = p_id;

  INSERT INTO public.complaint_events (complaint_id, actor_id, event_type, note, meta)
  VALUES (p_id, v_uid, 'resolved', v_res,
          jsonb_build_object('compensation_type', p_comp_type, 'amount', v_amount, 'funded_by', v_funded));

  RETURN jsonb_build_object('id', p_id, 'status', 'resolved', 'compensation_type', p_comp_type, 'amount', v_amount);
END;
$function$;

-- ===== ACL: authenticated only =====
REVOKE ALL ON FUNCTION public.create_complaint(uuid,text,text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.add_complaint_photo(uuid,text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.my_complaints() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.staff_list_complaints(text,integer,integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.staff_get_complaint(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.staff_add_complaint_note(uuid,text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.staff_assign_complaint(uuid,uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.staff_reject_complaint(uuid,text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.staff_resolve_complaint(uuid,text,text,numeric,text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_complaint(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_complaint_photo(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.my_complaints() TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_list_complaints(text,integer,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_get_complaint(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_add_complaint_note(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_assign_complaint(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_reject_complaint(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_resolve_complaint(uuid,text,text,numeric,text) TO authenticated;

COMMIT;
