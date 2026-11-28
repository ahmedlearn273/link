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
    country_id, city_id, area_id, country, city, area, address
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
    v_address
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
$function$

