-- d2a: whatsapp_number column + update_my_whatsapp (a user updates only their own number). Safe to run now.
BEGIN;

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS whatsapp_number text;

CREATE OR REPLACE FUNCTION public.update_my_whatsapp(p_whatsapp text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_role text;
  v_status text;
  v_old text;
  v_new text := btrim(coalesce(p_whatsapp, ''));
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF v_new !~ '^\+201[0125][0-9]{8}$' THEN
    RAISE EXCEPTION 'A valid Egyptian WhatsApp number is required (format +201XXXXXXXXX)' USING ERRCODE = '22023';
  END IF;
  SELECT p.role, p.status, p.whatsapp_number INTO v_role, v_status, v_old
  FROM public.profiles p WHERE p.id = v_uid FOR UPDATE;
  IF NOT FOUND OR v_role NOT IN ('customer','provider') THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;
  IF v_status = 'suspended' THEN
    RAISE EXCEPTION 'Account is suspended' USING ERRCODE = '42501';
  END IF;
  UPDATE public.profiles SET whatsapp_number = v_new, updated_at = now() WHERE id = v_uid;
  INSERT INTO public.audit_logs(actor_id, actor_role, action, entity_table, entity_id, old_data, new_data, event_source, result)
  VALUES (v_uid, v_role, 'WHATSAPP_UPDATED', 'profiles', v_uid::text,
    jsonb_build_object('last3', CASE WHEN v_old IS NULL THEN NULL ELSE right(v_old, 3) END),
    jsonb_build_object('last3', right(v_new, 3)), 'server_function', 'success');
END;
$function$;

REVOKE ALL ON FUNCTION public.update_my_whatsapp(text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_my_whatsapp(text) TO authenticated;

COMMIT;
