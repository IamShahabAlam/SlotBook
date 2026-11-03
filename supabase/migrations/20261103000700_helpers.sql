-- Internal helpers (schema private, never exposed by the API). RLS policies and every RPC build on these.
-- private.booking_json lives in the views migration because it reads public.booking_details.

-- Active user row of the caller (no device check). Used by audit, logs, own-device reads.
create or replace function private.current_user_id()
returns integer language sql stable security definer set search_path = ''
as $$
  select u.user_id from public.users u
  where u.auth_user_id = auth.uid() and u.data_status = 1
$$;

-- Client of the caller ONLY if this request comes from the user's active phone session.
-- Used by every RLS policy on client data: a replaced/old phone instantly reads nothing.
create or replace function private.session_client_id()
returns integer language sql stable security definer set search_path = ''
as $$
  select u.client_id
  from public.users u
  join public.clients c on c.client_id = u.client_id and c.data_status = 1
  join public.devices d on d.user_id = u.user_id and d.data_status = 1
                       and d.auth_session_id = nullif(auth.jwt() ->> 'session_id', '')::uuid
  where u.auth_user_id = auth.uid() and u.data_status = 1
$$;

-- Platform admin, and only with MFA (aal2).
create or replace function private.is_app_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.app_admins a
    where a.auth_user_id = auth.uid() and a.data_status = 1
      and coalesce(auth.jwt() ->> 'aal', '') = 'aal2')
$$;

create or replace function private.current_app_admin_id()
returns integer language sql stable security definer set search_path = ''
as $$
  select a.app_admin_id from public.app_admins a
  where a.auth_user_id = auth.uid() and a.data_status = 1
$$;

-- Effective right of the caller for a permission code.
create or replace function private.has_permission(p_code text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce((
    select case
             when r.is_full_access then true
             else coalesce((
               select crp.is_allowed
               from public.client_role_permissions crp
               join public.permissions p on p.permission_id = crp.permission_id and p.data_status = 1
               where crp.client_id = u.client_id
                 and crp.role_id = u.role_id
                 and crp.data_status = 1
                 and p.permission_code = p_code), false)
           end
    from public.users u
    join public.roles r on r.role_id = u.role_id and r.data_status = 1
    where u.auth_user_id = auth.uid() and u.data_status = 1), false)
$$;

-- Every write RPC starts with this. Returns the caller's user and client, or raises.
create or replace function private.require_session(out o_user_id integer, out o_client_id integer)
language plpgsql stable security definer set search_path = ''
as $$
begin
  select u.user_id, u.client_id into o_user_id, o_client_id
  from public.users u
  join public.clients c on c.client_id = u.client_id and c.data_status = 1
  where u.auth_user_id = auth.uid() and u.data_status = 1;

  if o_user_id is null then
    raise exception using errcode = 'AB001', message = 'Your account is not active for this business.';
  end if;

  if not exists (
    select 1 from public.devices d
    where d.user_id = o_user_id and d.data_status = 1
      and d.auth_session_id = nullif(auth.jwt() ->> 'session_id', '')::uuid) then
    raise exception using errcode = 'AB002',
      message = 'You were signed out because your account signed in on another phone.';
  end if;
end;
$$;

create or replace function private.require_permission(p_code text)
returns void language plpgsql stable security definer set search_path = ''
as $$
begin
  if not private.has_permission(p_code) then
    raise exception using errcode = 'AB010', message = 'You do not have permission to do this.';
  end if;
end;
$$;

-- Same rules as the old Gist switch.
create or replace function private.is_license_writable(p_client_id integer)
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce((
    select case
             when l.data_status <> 1 then true          -- entry ignored → app runs (Gist rule)
             when l.is_app_enable then true
             when l.app_disable_after_date is null then false
             else (now() at time zone c.timezone)::date <= l.app_disable_after_date
           end
    from public.licenses l
    join public.clients c on c.client_id = l.client_id
    where l.client_id = p_client_id), false)           -- no licence row → blocked (fail closed)
$$;

create or replace function private.require_writable_license(p_client_id integer)
returns void language plpgsql stable security definer set search_path = ''
as $$
begin
  if not private.is_license_writable(p_client_id) then
    raise exception using errcode = 'AB003', message = 'Your licence is not active. Please contact support.';
  end if;
end;
$$;

-- Admin-only functions: allowed from SQL editor / migrations (session_user is not 'authenticator'),
-- from the service key, or from an app admin with MFA.
create or replace function private.require_admin()
returns void language plpgsql stable security definer set search_path = ''
as $$
begin
  if session_user = 'authenticator'
     and coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
     and not private.is_app_admin() then
    raise exception using errcode = 'AB010', message = 'Admin only.';
  end if;
end;
$$;
