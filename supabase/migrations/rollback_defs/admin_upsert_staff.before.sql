CREATE OR REPLACE FUNCTION public.admin_upsert_staff(p_user_id uuid, p_permissions text[], p_is_active boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_role text; v_status text; v_actor uuid := (SELECT auth.uid());
  v_actor_role text; v_actor_code text; v_old_permissions text[];
  v_old_active boolean; v_effective_active boolean;
BEGIN
  IF v_actor IS NULL OR NOT private.is_active_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_user_id IS NULL OR p_user_id = v_actor THEN RAISE EXCEPTION 'Invalid staff account'; END IF;
  IF coalesce(p_permissions,ARRAY[]::text[]) && ARRAY['customers.contact','reports.export','reports.import']::text[] THEN
    RAISE EXCEPTION 'Restricted administrative permissions cannot be assigned to staff';
  END IF;
  SELECT p.role,p.status INTO v_role,v_status FROM public.profiles p WHERE p.id=p_user_id FOR UPDATE;
  IF NOT FOUND OR v_role <> 'staff' THEN RAISE EXCEPTION 'Only existing staff accounts can be managed'; END IF;
  SELECT sp.permissions,sp.is_active INTO v_old_permissions,v_old_active
    FROM public.staff_permissions sp WHERE sp.user_id=p_user_id FOR UPDATE;
  v_effective_active := coalesce(p_is_active,true) AND v_status='active';
  INSERT INTO public.staff_permissions(user_id,permissions,is_active,created_by)
  VALUES(p_user_id,coalesce(p_permissions,'{}'::text[]),v_effective_active,v_actor)
  ON CONFLICT(user_id) DO UPDATE SET permissions=EXCLUDED.permissions,is_active=v_effective_active,updated_at=now();
  SELECT p.role,p.account_code INTO v_actor_role,v_actor_code FROM public.profiles p WHERE p.id=v_actor;
  INSERT INTO public.audit_logs(actor_id,actor_role,actor_code,action,entity_table,entity_id,old_data,new_data,event_source,result)
  VALUES(v_actor,v_actor_role,v_actor_code,'STAFF_PERMISSIONS_UPDATED','staff_permissions',p_user_id::text,
    private.audit_sanitize(jsonb_build_object('permissions',v_old_permissions,'is_active',v_old_active)),
    private.audit_sanitize(jsonb_build_object('permissions',coalesce(p_permissions,'{}'::text[]),'is_active',v_effective_active)),
    'server_function','success');
END;
$function$

