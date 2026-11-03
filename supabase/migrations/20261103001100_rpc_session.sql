-- Session and configuration RPCs: licence check (anon), phone binding, sign-out, client bundle.

-- Licence entry in the old Gist JSON shape, so AppAccessService's rules stay the same.
create or replace function public.get_app_access(p_client_code text)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'found', l.license_id is not null,
    'entry', case when l.license_id is null then null else jsonb_build_object(
        'IsAppEnable',         l.is_app_enable,
        'AppDisableAfterDate', coalesce(to_char(l.app_disable_after_date, 'YYYY-MM-DD'), ''),
        'DataEntryStatus',     l.data_status,
        'DataEntryDate',       to_char(l.created_at at time zone c.timezone, 'YYYY-MM-DD'),
        'LastUpdateDate',      to_char(l.updated_at at time zone c.timezone, 'YYYY-MM-DD'),
        'UserName',            coalesce(a.full_name, ''))
      end,
    'server_time', now())
  from (select 1) as one
  left join public.clients c   on c.client_code = p_client_code and c.data_status = 1
  left join public.licenses l  on l.client_id = c.client_id
  left join public.app_admins a on a.app_admin_id = l.updated_by_app_admin_id
$$;

-- Binds this phone to the user. Another active phone → 'other_device_active' unless p_replace_other.
create or replace function public.start_session(
  p_client_code        text,
  p_device_uid         text,
  p_platform_device_id text,
  p_device_name        text,
  p_platform           text,
  p_app_version        text,
  p_replace_other      boolean default false)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_user        public.users;
  v_client_code text;
  v_session     uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  v_active      public.devices;
  v_device_id   integer;
  v_replaced    boolean := false;
begin
  select u.* into v_user from public.users u
  where u.auth_user_id = auth.uid() and u.data_status = 1;
  if not found then
    raise exception using errcode = 'AB001',
      message = 'This email is not registered. Ask the business owner to add you.';
  end if;

  select c.client_code into v_client_code from public.clients c
  where c.client_id = v_user.client_id and c.data_status = 1;
  if v_client_code is distinct from p_client_code then
    raise exception using errcode = 'AB004', message = 'This account belongs to a different business.';
  end if;

  if v_session is null then
    raise exception using errcode = 'AB001', message = 'Invalid session. Please sign in again.';
  end if;

  select d.* into v_active from public.devices d
  where d.user_id = v_user.user_id and d.data_status = 1
  for update;

  if found then
    if v_active.device_uid = p_device_uid then
      -- same phone signing in again: refresh its session
      update public.devices
         set auth_session_id = v_session, device_name = p_device_name,
             platform_device_id = coalesce(p_platform_device_id, ''),
             app_version = p_app_version, last_seen_at = now()
       where device_id = v_active.device_id;
      return jsonb_build_object('status', 'ok', 'device_id', v_active.device_id,
                                'replaced_other', false, 'server_time', now());
    elsif not p_replace_other then
      return jsonb_build_object('status', 'other_device_active',
                                'other_device_name', v_active.device_name,
                                'other_last_seen_at', v_active.last_seen_at,
                                'server_time', now());
    end if;
    update public.devices set data_status = 0 where device_id = v_active.device_id;
    v_replaced := true;
  end if;

  insert into public.devices (user_id, client_id, auth_session_id, device_uid, platform_device_id,
                              device_name, platform, app_version, last_seen_at)
  values (v_user.user_id, v_user.client_id, v_session, p_device_uid, coalesce(p_platform_device_id, ''),
          coalesce(p_device_name, ''), p_platform, coalesce(p_app_version, ''), now())
  returning device_id into v_device_id;

  return jsonb_build_object('status', 'ok', 'device_id', v_device_id,
                            'replaced_other', v_replaced, 'server_time', now());
exception
  when unique_violation then   -- another phone became active at the same instant
    return jsonb_build_object('status', 'other_device_active', 'server_time', now());
end;
$$;

-- Deactivates this phone; the app calls auth.signOut() right after.
create or replace function public.sign_out_device()
returns void
language sql security definer set search_path = ''
as $$
  update public.devices
     set data_status = 0
   where user_id = private.current_user_id()
     and data_status = 1
     and auth_session_id = nullif(auth.jwt() ->> 'session_id', '')::uuid
$$;

-- Everything the phone needs about its client. Disabled types/resources are included so old bookings still render.
create or replace function public.get_client_bundle(p_app_version text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_ctx record;
begin
  select * into v_ctx from private.require_session();

  update public.devices
     set last_seen_at = now(), app_version = coalesce(p_app_version, app_version)
   where user_id = v_ctx.o_user_id and data_status = 1;

  return jsonb_build_object(
    'client', (select to_jsonb(c) from public.clients c where c.client_id = v_ctx.o_client_id),
    'business_profile_code', (select bp.profile_code
                                from public.clients c
                                join public.business_profiles bp on bp.business_profile_id = c.business_profile_id
                               where c.client_id = v_ctx.o_client_id),
    'user', (select jsonb_build_object('user_id', u.user_id, 'full_name', u.full_name, 'email', u.email,
                                       'role_id', u.role_id, 'role_code', r.role_code,
                                       'is_full_access', r.is_full_access)
               from public.users u join public.roles r on r.role_id = u.role_id
              where u.user_id = v_ctx.o_user_id),
    'permissions', (select coalesce(jsonb_agg(p.permission_code order by p.sort_order), '[]'::jsonb)
                      from public.permissions p
                     where p.data_status = 1 and private.has_permission(p.permission_code)),
    'resource_types', (select coalesce(jsonb_agg(to_jsonb(t) order by t.sort_order, t.resource_type_id), '[]'::jsonb)
                         from public.resource_types t where t.client_id = v_ctx.o_client_id),
    'resources', (select coalesce(jsonb_agg(to_jsonb(r) order by r.sort_order, r.resource_id), '[]'::jsonb)
                    from public.resources r where r.client_id = v_ctx.o_client_id),
    'booking_sessions', (select coalesce(jsonb_agg(to_jsonb(s) order by s.sort_order, s.start_minute), '[]'::jsonb)
                           from public.booking_sessions s
                          where s.client_id = v_ctx.o_client_id and s.data_status = 1),
    'server_time', now());
end;
$$;
