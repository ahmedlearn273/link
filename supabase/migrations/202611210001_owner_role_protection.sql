
-- =========================================================
-- WASLA: Owner Role Protection
-- Migration: 202611210001_owner_role_protection.sql
-- =========================================================

-- 1. Allow the owner role.
alter table public.profiles
  drop constraint if exists profiles_role_check;

alter table public.profiles
  add constraint profiles_role_check
  check (role in ('customer', 'provider', 'admin', 'staff', 'owner'));

-- 2. Enforce a single owner account.
create unique index if not exists profiles_single_owner_uidx
  on public.profiles (role)
  where role = 'owner';

-- 3. Protect owner privileges and profile deletion.
create or replace function private.guard_owner_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  -- Only trusted database administration sessions may
  -- create, promote, demote, suspend, or delete an owner.
  if TG_OP = 'INSERT' then
    if NEW.role = 'owner'
       and session_user not in ('postgres', 'supabase_admin') then
      raise exception 'Owner creation is restricted';
    end if;

    return NEW;
  end if;

  if TG_OP = 'DELETE' then
    if OLD.role = 'owner'
       and session_user not in ('postgres', 'supabase_admin') then
      raise exception 'Owner account cannot be deleted';
    end if;

    return OLD;
  end if;

  if TG_OP = 'UPDATE' then
    if (OLD.role = 'owner' OR NEW.role = 'owner')
       and (
         NEW.role is distinct from OLD.role
         or NEW.status is distinct from OLD.status
       )
       and session_user not in ('postgres', 'supabase_admin') then
      raise exception 'Owner role and status are protected';
    end if;

    return NEW;
  end if;

  return null;
end;
$function$;

revoke all on function private.guard_owner_profile()
  from public, anon, authenticated, service_role;

drop trigger if exists guard_owner_profile_changes
  on public.profiles;

create trigger guard_owner_profile_changes
before insert or update or delete
on public.profiles
for each row
execute function private.guard_owner_profile();

-- 4. Protect the owner from deletion through Supabase Auth.
create or replace function private.guard_owner_auth_deletion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if session_user not in ('postgres', 'supabase_admin')
     and exists (
       select 1
       from public.profiles p
       where p.id = OLD.id
         and p.role = 'owner'
     ) then
    raise exception 'Owner Auth account cannot be deleted';
  end if;

  return OLD;
end;
$function$;

revoke all on function private.guard_owner_auth_deletion()
  from public, anon, authenticated, service_role;

drop trigger if exists guard_owner_auth_deletion
  on auth.users;

create trigger guard_owner_auth_deletion
before delete
on auth.users
for each row
execute function private.guard_owner_auth_deletion();

-- =========================================================
-- End of owner protection migration
-- =========================================================

