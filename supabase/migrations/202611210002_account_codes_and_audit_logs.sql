
-- =========================================================
-- WASLA - Account Codes, Immutable Roles and Audit Logs
-- Stage 1 / Part 1.2
-- =========================================================

-- 1. Account role constraint
alter table public.profiles
  drop constraint if exists profiles_role_check;

alter table public.profiles
  add constraint profiles_role_check
  check (role in ('customer', 'provider', 'staff', 'admin', 'owner'));

-- 2. Account code column
alter table public.profiles
  add column if not exists account_code text;

-- Verify the four existing accounts before assigning codes.
do $$
begin
  if (
    select count(*)
    from public.profiles
    where id in (
      '223c25dd-4e7e-4ba1-8f48-24c4bdf8c9be',
      '9af2c3fb-9077-405e-b247-a176a696fbb0',
      '7a0f43f8-c7e3-4235-a5c7-2b2f3836dde8',
      '394d813f-515e-43ff-913b-f347e96194dd'
    )
  ) <> 4 then
    raise exception 'Existing account verification failed. Migration stopped.';
  end if;
end;
$$;

-- Preserve all existing account roles and assign their codes.
update public.profiles
set account_code = case id
  when '223c25dd-4e7e-4ba1-8f48-24c4bdf8c9be' then 'ADM00001'
  when '9af2c3fb-9077-405e-b247-a176a696fbb0' then 'PRV00001'
  when '7a0f43f8-c7e3-4235-a5c7-2b2f3836dde8' then 'CLT00001'
  when '394d813f-515e-43ff-913b-f347e96194dd' then 'STF00001'
  else account_code
end
where id in (
  '223c25dd-4e7e-4ba1-8f48-24c4bdf8c9be',
  '9af2c3fb-9077-405e-b247-a176a696fbb0',
  '7a0f43f8-c7e3-4235-a5c7-2b2f3836dde8',
  '394d813f-515e-43ff-913b-f347e96194dd'
);

alter table public.profiles
  alter column account_code set not null;

create unique index if not exists profiles_account_code_uidx
  on public.profiles(account_code);

-- 3. Independent account-code sequences.
create table if not exists private.account_code_sequences (
  account_role text primary key,
  prefix text not null unique,
  next_value bigint not null check (next_value > 0)
);

revoke all on private.account_code_sequences
  from public, anon, authenticated, service_role;

insert into private.account_code_sequences
  (account_role, prefix, next_value)
values
  ('customer', 'CLT', 2),
  ('provider', 'PRV', 2),
  ('staff', 'STF', 2),
  ('admin', 'ADM', 2),
  ('owner', 'OWN', 1)
on conflict (account_role) do nothing;

-- 4. Generate codes automatically on account creation.
create or replace function private.assign_account_code()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_prefix text;
  v_number bigint;
begin
  select prefix
  into v_prefix
  from private.account_code_sequences
  where account_role = new.role;

  if not found then
    raise exception 'Unsupported account role';
  end if;

  update private.account_code_sequences
  set next_value = next_value + 1
  where account_role = new.role
  returning next_value - 1 into v_number;

  new.account_code :=
    v_prefix || lpad(v_number::text, 5, '0');

  return new;
end;
$function$;

revoke all on function private.assign_account_code()
  from public, anon, authenticated, service_role;

drop trigger if exists assign_profile_account_code
  on public.profiles;

create trigger assign_profile_account_code
before insert on public.profiles
for each row
execute function private.assign_account_code();

-- 5. Prevent account-role and account-code changes.
create or replace function private.prevent_account_identity_change()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.role is distinct from old.role then
    raise exception 'Account role cannot be changed';
  end if;

  if new.account_code is distinct from old.account_code then
    raise exception 'Account code cannot be changed';
  end if;

  return new;
end;
$function$;

revoke all on function private.prevent_account_identity_change()
  from public, anon, authenticated, service_role;

drop trigger if exists prevent_account_identity_change
  on public.profiles;

create trigger prevent_account_identity_change
before update on public.profiles
for each row
execute function private.prevent_account_identity_change();

-- 6. Allow the owner and active admins to use admin-level checks.
create or replace function private.is_active_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role in ('admin', 'owner')
      and p.status = 'active'
  );
$function$;

-- 7. Staff management must never convert account roles.
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

create or replace function public.admin_remove_staff(
  p_user_id uuid
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

  select role into v_role
  from public.profiles
  where id = p_user_id
  for update;

  if not found or v_role <> 'staff' then
    raise exception 'Staff account not found';
  end if;

  update public.staff_permissions
  set is_active = false,
      updated_at = now()
  where user_id = p_user_id;

  update public.profiles
  set status = 'inactive',
      updated_at = now()
  where id = p_user_id;
end;
$function$;

-- 8. Central audit log.
create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid,
  actor_role text,
  actor_code text,
  action text not null,
  entity_table text not null,
  entity_id text,
  old_data jsonb,
  new_data jsonb,
  event_source text not null default 'database_trigger',
  created_at timestamptz not null default now()
);

create index if not exists audit_logs_created_at_idx
  on public.audit_logs(created_at desc);

create index if not exists audit_logs_actor_id_idx
  on public.audit_logs(actor_id);

create index if not exists audit_logs_entity_idx
  on public.audit_logs(entity_table, entity_id);

alter table public.audit_logs enable row level security;

revoke all on public.audit_logs
  from public, anon, authenticated;

grant select on public.audit_logs to authenticated;

drop policy if exists "Admins and owner can view audit logs"
  on public.audit_logs;

create policy "Admins and owner can view audit logs"
on public.audit_logs
for select
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role in ('admin', 'owner')
      and p.status = 'active'
  )
);

-- 9. Redact sensitive values before storing audit snapshots.
create or replace function private.audit_sanitize(p_data jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  if p_data is null or jsonb_typeof(p_data) <> 'object' then
    return p_data;
  end if;

  select coalesce(
    jsonb_object_agg(
      key,
      case
        when lower(key) in (
          'password', 'encrypted_password', 'token',
          'access_token', 'refresh_token', 'secret',
          'email', 'phone', 'address', 'message_text',
          'full_name', 'bio', 'description'
        )
        then '"[REDACTED]"'::jsonb
        else value
      end
    ),
    '{}'::jsonb
  )
  into v_result
  from jsonb_each(p_data);

  return v_result;
end;
$function$;

revoke all on function private.audit_sanitize(jsonb)
  from public, anon, authenticated, service_role;

-- 10. Capture database row changes.
create or replace function private.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_old jsonb;
  v_new jsonb;
  v_actor uuid;
  v_role text;
  v_code text;
  v_entity_id text;
begin
  v_actor := auth.uid();

  if tg_op = 'INSERT' then
    v_new := to_jsonb(new);
    v_entity_id := coalesce(
      v_new ->> 'id',
      v_new ->> 'user_id',
      v_new ->> 'request_id'
    );
  elsif tg_op = 'UPDATE' then
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
    v_entity_id := coalesce(
      v_new ->> 'id',
      v_new ->> 'user_id',
      v_new ->> 'request_id'
    );
  elsif tg_op = 'DELETE' then
    v_old := to_jsonb(old);
    v_entity_id := coalesce(
      v_old ->> 'id',
      v_old ->> 'user_id',
      v_old ->> 'request_id'
    );
  end if;

  if v_actor is not null then
    select p.role, p.account_code
    into v_role, v_code
    from public.profiles p
    where p.id = v_actor;
  end if;

  insert into public.audit_logs (
    actor_id,
    actor_role,
    actor_code,
    action,
    entity_table,
    entity_id,
    old_data,
    new_data
  )
  values (
    v_actor,
    coalesce(v_role, 'system'),
    v_code,
    tg_op,
    tg_table_name,
    v_entity_id,
    private.audit_sanitize(v_old),
    private.audit_sanitize(v_new)
  );

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$function$;

revoke all on function private.audit_row_change()
  from public, anon, authenticated, service_role;

-- 11. Attach audit triggers to existing business tables.
do $$
declare
  v_table text;
  v_tables text[] := array[
    'profiles',
    'provider_profiles',
    'staff_permissions',
    'categories',
    'services',
    'provider_services',
    'service_requests',
    'conversations',
    'messages',
    'favorites',
    'notifications',
    'payments',
    'reviews'
  ];
begin
  foreach v_table in array v_tables loop
    execute format(
      'drop trigger if exists audit_row_change on public.%I',
      v_table
    );

    execute format(
      'create trigger audit_row_change
       after insert or update or delete on public.%I
       for each row execute function private.audit_row_change()',
      v_table
    );
  end loop;
end;
$$;

-- =========================================================
-- End of migration
-- =========================================================
