-- D-whatsapp: whatsapp_number column, mandatory for NEW customer/provider-application signups, and update_my_whatsapp.
-- Old accounts are not changed. Staff/admin/owner and admin-created accounts are exempt.
-- DEPLOY ORDER: the signup screens must send raw_user_meta_data.whatsapp_number BEFORE this runs.
BEGIN;

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS whatsapp_number text;

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text;
  v_experience integer;
  v_country_id uuid;
  v_city_id uuid;
  v_area_id uuid;
  v_country_name text;
  v_city_name text;
  v_area_name text;
  v_address text;
  v_signup_token text;
  v_whatsapp text;
begin
  v_signup_token := nullif(new.raw_user_meta_data ->> 'provider_signup_token','');

  if new.raw_app_meta_data ->> 'account_role' = 'staff' then
    v_role := 'staff';
  elsif new.raw_app_meta_data ->> 'account_role' = 'provider' then
    v_role := 'provider';
  elsif v_signup_token is not null then
    if private.consume_provider_signup_token(v_signup_token) then
      v_role := 'provider';
    else
      raise exception 'Provider application documents are missing, invalid, or expired'
        using errcode='22023';
    end if;
  else
    v_role := 'customer';
  end if;

  if v_role = 'customer' or (v_role = 'provider' and v_signup_token is not null) then
    v_whatsapp := nullif(btrim(new.raw_user_meta_data ->> 'whatsapp_number'),'');
    if v_whatsapp is null or v_whatsapp !~ '^\+201[0125][0-9]{8}$' then
      raise exception 'A valid Egyptian WhatsApp number is required (format +201XXXXXXXXX)'
        using errcode='22023';
    end if;
  end if;

  v_experience := case
    when coalesce(new.raw_user_meta_data ->> 'experience_years','') ~ '^[0-9]{1,2}$'
      then least((new.raw_user_meta_data ->> 'experience_years')::integer, 80)
    else 0
  end;

  if v_role = 'provider'
     and (
       nullif(new.raw_user_meta_data ->> 'country_id','') is null
       or nullif(new.raw_user_meta_data ->> 'city_id','') is null
       or nullif(new.raw_user_meta_data ->> 'area_id','') is null
     ) then
    raise exception 'Country, governorate and subdivision are required for provider accounts'
      using errcode='22023';
  end if;

  if nullif(new.raw_user_meta_data ->> 'country_id','') is not null
     or nullif(new.raw_user_meta_data ->> 'city_id','') is not null
     or nullif(new.raw_user_meta_data ->> 'area_id','') is not null then
    begin
      v_country_id := nullif(new.raw_user_meta_data ->> 'country_id','')::uuid;
      v_city_id := nullif(new.raw_user_meta_data ->> 'city_id','')::uuid;
      v_area_id := nullif(new.raw_user_meta_data ->> 'area_id','')::uuid;
    exception when others then
      raise exception 'Invalid geographic identifiers' using errcode='22023';
    end;

    if v_country_id is null or v_city_id is null or v_area_id is null then
      raise exception 'Country, governorate and subdivision are required' using errcode='22023';
    end if;

    select co.name_ar, c.name_ar, a.name_ar
      into v_country_name, v_city_name, v_area_name
    from private.geo_countries co
    join private.geo_cities c on c.country_id=co.id
    join private.geo_areas a on a.city_id=c.id
    where co.id=v_country_id and c.id=v_city_id and a.id=v_area_id
      and co.country_code='EG'
      and co.is_active=true and c.is_active=true and a.is_active=true;

    if not found then
      raise exception 'Selected geographic location is invalid or inactive'
        using errcode='22023';
    end if;

    v_address := nullif(btrim(new.raw_user_meta_data ->> 'address'),'');
    if v_address is null or length(v_address)>500 then
      raise exception 'Detailed address is required (maximum 500 characters)'
        using errcode='22023';
    end if;
  end if;

  insert into public.profiles (
    id, full_name, phone, role, status, must_change_password,
    country_id, city_id, area_id, country, city, area, address, whatsapp_number
  )
  values (
    new.id,
    nullif(new.raw_user_meta_data ->> 'full_name',''),
    nullif(new.phone,''),
    v_role,
    case when v_role = 'provider' then 'pending' else 'active' end,
    false,
    v_country_id,
    v_city_id,
    v_area_id,
    coalesce(v_country_name,nullif(new.raw_user_meta_data ->> 'country','')),
    coalesce(v_city_name,nullif(new.raw_user_meta_data ->> 'city','')),
    v_area_name,
    v_address,
    v_whatsapp
  );

  if v_role = 'provider' then
    insert into public.provider_profiles (
      user_id, display_name, bio, experience_years,
      country, city, service_area, verification_status, is_available,
      country_id, city_id, area_id, address
    )
    values (
      new.id,
      nullif(new.raw_user_meta_data ->> 'full_name',''),
      nullif(new.raw_user_meta_data ->> 'bio',''),
      v_experience,
      coalesce(v_country_name,nullif(new.raw_user_meta_data ->> 'country','')),
      coalesce(v_city_name,nullif(new.raw_user_meta_data ->> 'city','')),
      nullif(new.raw_user_meta_data ->> 'service_area',''),
      'pending',
      false,
      v_country_id,
      v_city_id,
      v_area_id,
      v_address
    );

    if v_signup_token is not null then
      update private.provider_application_documents
         set user_id = new.id,
             signup_token = null
       where signup_token = v_signup_token::uuid;
    end if;
  end if;

  return new;
end;
$function$;

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
