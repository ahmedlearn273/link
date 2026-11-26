-- =========================================================
-- WASLA - Phase 0 / Part 1: DB-level staff permission protection
-- Migration: 202611260001_phase0_permissions_foundation.sql
-- Idempotent: safe to run more than once. Deletes no data, changes no role or owner.
-- Depends on (already live): public.profiles, public.staff_permissions,
--   private.is_active_admin(), public.admin_upsert_staff, public.audit_logs,
--   private.audit_row_change()
-- =========================================================

begin;

-- 1. Single source of truth for allowed permission keys (19 existing + 7 new).
create or replace function private.staff_permission_catalog()
returns text[]
language sql
immutable
set search_path = ''
as $function$
  select array[
    'dashboard.view',
    'customers.view','customers.manage','customers.contact',
    'providers.view','providers.review',
    'requests.view','requests.manage',
    'services.view','services.manage',
    'categories.view','categories.manage',
    'messages.view',
    'payments.view','payments.manage',
    'reports.view','reports.export','reports.import',
    'ads.view','ads.manage',
    'settings.view','settings.manage',
    'support.view','support.manage',
    'wallet.view','wallet.manage'
  ]::text[];
$function$;

-- 2. private.has_permission(p): active owner/admin, or active staff holding p.
--    Evaluated on every call, so a revoked permission fails on the next call.
create or replace function private.has_permission(p text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(p, '') <> ''
    and exists (
      select 1
      from public.profiles pr
      where pr.id = (select auth.uid())
        and pr.status = 'active'
        and (
          pr.role in ('admin', 'owner')
          or (
            pr.role = 'staff'
            and exists (
              select 1
              from public.staff_permissions sp
              where sp.user_id = pr.id
                and sp.is_active
                and p = any (sp.permissions)
            )
          )
        )
    );
$function$;

-- 3. Staff areas (empty = unrestricted, except ASV where empty = sees nothing).
--    area_id has no foreign key on purpose: the geo catalog table was not
--    readable when this was written. Add the FK once its name is confirmed.
create table if not exists public.staff_areas (
  user_id uuid not null references public.profiles(id) on delete cascade,
  area_id uuid not null,
  created_by uuid,
  created_at timestamptz not null default now(),
  primary key (user_id, area_id)
);

create index if not exists staff_areas_area_idx on public.staff_areas(area_id);

alter table public.staff_areas enable row level security;

revoke all on public.staff_areas from public, anon, authenticated;
grant select on public.staff_areas to authenticated;

drop policy if exists "Staff areas readable by self and admins" on public.staff_areas;
create policy "Staff areas readable by self and admins"
on public.staff_areas
for select
to authenticated
using (
  user_id = (select auth.uid())
  or (select private.is_active_admin())
);

-- 4. private.staff_in_area(area_id)
--    Admin/owner: true. Staff with areas: true only inside them.
--    Staff without areas: true only if their rank is known and is not ASV
--    (unknown rank is treated as ASV = safe default).
--    Rank is read from staff_permissions or profiles if a staff_role_code
--    column exists there, without failing if it does not.
create or replace function private.staff_in_area(p_area_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_role text;
  v_status text;
  v_active boolean;
  v_rank text;
begin
  if v_uid is null then
    return false;
  end if;

  select pr.role, pr.status,
         nullif(to_jsonb(pr) ->> 'staff_role_code', '')
  into v_role, v_status, v_rank
  from public.profiles pr
  where pr.id = v_uid;

  if not found or v_status <> 'active' then
    return false;
  end if;

  if v_role in ('admin', 'owner') then
    return true;
  end if;

  if v_role <> 'staff' then
    return false;
  end if;

  select sp.is_active,
         coalesce(v_rank, nullif(to_jsonb(sp) ->> 'staff_role_code', ''))
  into v_active, v_rank
  from public.staff_permissions sp
  where sp.user_id = v_uid;

  if not found or not coalesce(v_active, false) then
    return false;
  end if;

  if exists (select 1 from public.staff_areas sa where sa.user_id = v_uid) then
    return p_area_id is not null
      and exists (
        select 1 from public.staff_areas sa
        where sa.user_id = v_uid and sa.area_id = p_area_id
      );
  end if;

  return v_rank is not null and upper(v_rank) <> 'ASV';
end;
$function$;

-- 5. Customer contact data (phone, address) only with customers.contact.
create or replace function private.contact_or_null(p_value text)
returns text
language sql
stable
set search_path = ''
as $function$
  select case when private.has_permission('customers.contact') then p_value else null end;
$function$;

-- 6. platform_settings
create table if not exists public.platform_settings (
  key text primary key,
  value jsonb not null,
  updated_by uuid,
  updated_at timestamptz not null default now()
);

alter table public.platform_settings enable row level security;

revoke all on public.platform_settings from public, anon, authenticated;
grant select on public.platform_settings to authenticated;

drop policy if exists "Admins and owner can view settings" on public.platform_settings;
create policy "Admins and owner can view settings"
on public.platform_settings
for select
to authenticated
using ((select private.is_active_admin()));

-- No direct write policy: changes go through a validated RPC (Part 9),
-- or the SQL editor as postgres.

insert into public.platform_settings (key, value) values
  ('commission_rate', '0.10'::jsonb),
  ('wallet_negative_cap', '500'::jsonb),
  ('late_no_provider_hours', '48'::jsonb),
  ('late_after_scheduled_hours', '24'::jsonb),
  ('ops_compensation_limit', '200'::jsonb),
  ('support_first_response_hours', '4'::jsonb),
  ('weekly_settlement_day', '"thursday"'::jsonb)
on conflict (key) do nothing;

create or replace function private.get_setting(p_key text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select value from public.platform_settings where key = p_key;
$function$;

-- 7. Function privileges: callable from other functions, not from anon/public.
revoke all on function private.staff_permission_catalog() from public, anon;
revoke all on function private.has_permission(text) from public, anon;
revoke all on function private.staff_in_area(uuid) from public, anon;
revoke all on function private.contact_or_null(text) from public, anon;
revoke all on function private.get_setting(text) from public, anon;
grant execute on function private.staff_permission_catalog() to authenticated;
grant execute on function private.has_permission(text) to authenticated;
grant execute on function private.staff_in_area(uuid) to authenticated;
grant execute on function private.contact_or_null(text) to authenticated;
grant execute on function private.get_setting(text) to authenticated;

-- 8. admin_upsert_staff: same behavior as before, plus rejects unknown permission keys.
create or replace function public.admin_upsert_staff(
  p_user_id uuid,
  p_permissions text[],
  p_is_active boolean default true
)
returns void
language plpgsql
set search_path = ''
as $function$
declare
  v_role text;
begin
  if (select auth.uid()) is null
     or not private.is_active_admin() then
    raise exception 'Not authorized';
  end if;

  if p_user_id is null
     or p_user_id = (select auth.uid()) then
    raise exception 'Invalid staff account';
  end if;

  if exists (
    select 1
    from unnest(coalesce(p_permissions, '{}'::text[])) as x(k)
    where x.k <> all (private.staff_permission_catalog())
  ) then
    raise exception 'Invalid permission';
  end if;

  select role into v_role
  from public.profiles
  where id = p_user_id
  for update;

  if not found or v_role <> 'staff' then
    raise exception 'Only existing staff accounts can be managed';
  end if;

  update public.profiles
  set status = 'active',
      updated_at = now()
  where id = p_user_id;

  insert into public.staff_permissions (
    user_id, permissions, is_active, created_by
  )
  values (
    p_user_id,
    coalesce(p_permissions, '{}'::text[]),
    coalesce(p_is_active, true),
    (select auth.uid())
  )
  on conflict (user_id) do update
  set permissions = excluded.permissions,
      is_active = excluded.is_active,
      updated_at = now();
end;
$function$;

-- 9. admin_set_staff_areas: owner/admin only, existing staff only, not self.
create or replace function public.admin_set_staff_areas(
  p_user_id uuid,
  p_area_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_role text;
begin
  if (select auth.uid()) is null
     or not private.is_active_admin() then
    raise exception 'Not authorized';
  end if;

  if p_user_id is null
     or p_user_id = (select auth.uid()) then
    raise exception 'Invalid staff account';
  end if;

  select role into v_role
  from public.profiles
  where id = p_user_id
  for update;

  if not found or v_role <> 'staff' then
    raise exception 'Staff account not found';
  end if;

  delete from public.staff_areas
  where user_id = p_user_id
    and area_id <> all (coalesce(p_area_ids, '{}'::uuid[]));

  insert into public.staff_areas (user_id, area_id, created_by)
  select p_user_id, a, (select auth.uid())
  from unnest(coalesce(p_area_ids, '{}'::uuid[])) as a
  on conflict (user_id, area_id) do nothing;
end;
$function$;

revoke all on function public.admin_set_staff_areas(uuid, uuid[]) from public, anon;
grant execute on function public.admin_set_staff_areas(uuid, uuid[]) to authenticated;

-- 10. Audit the new tables with the existing trigger function.
drop trigger if exists audit_row_change on public.staff_areas;
create trigger audit_row_change
after insert or update or delete on public.staff_areas
for each row execute function private.audit_row_change();

drop trigger if exists audit_row_change on public.platform_settings;
create trigger audit_row_change
after insert or update or delete on public.platform_settings
for each row execute function private.audit_row_change();

commit;
