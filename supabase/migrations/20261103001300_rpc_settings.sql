-- Settings, staff rights, users and app-event logging RPCs.

-- Changes a rate for new bookings; existing bookings keep their frozen rate.
create or replace function public.update_hourly_rate(p_resource_type_id integer, p_hourly_rate integer)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_ctx record;
begin
  select * into v_ctx from private.require_session();
  perform private.require_permission('settings.edit');
  perform private.require_writable_license(v_ctx.o_client_id);

  if p_hourly_rate is null or p_hourly_rate < 1 or p_hourly_rate > 1000000 then
    raise exception using errcode = 'AB029', message = 'Rate must be between 1 and 1,000,000.';
  end if;

  update public.resource_types
     set hourly_rate = p_hourly_rate
   where resource_type_id = p_resource_type_id and client_id = v_ctx.o_client_id;
  if not found then
    raise exception using errcode = 'AB040', message = 'Resource type not found.';
  end if;
end;
$$;

create or replace function public.update_client_settings(p_currency_symbol text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_ctx    record;
  v_symbol text := trim(coalesce(p_currency_symbol, ''));
begin
  select * into v_ctx from private.require_session();
  perform private.require_permission('settings.edit');
  perform private.require_writable_license(v_ctx.o_client_id);

  if char_length(v_symbol) not between 1 and 5 then
    raise exception using errcode = 'AB029', message = 'Currency symbol must be 1 to 5 characters.';
  end if;

  update public.clients set currency_symbol = v_symbol where client_id = v_ctx.o_client_id;
end;
$$;

-- Changes this client's rights for a non-owner role. Owner rights are fixed.
create or replace function public.set_role_permission(p_role_id integer, p_permission_id integer, p_is_allowed boolean)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_ctx record;
begin
  select * into v_ctx from private.require_session();
  perform private.require_permission('users.manage');

  if not exists (select 1 from public.roles r
                  where r.role_id = p_role_id and r.data_status = 1 and not r.is_full_access) then
    raise exception using errcode = 'AB010', message = 'Owner rights cannot be changed.';
  end if;
  if not exists (select 1 from public.permissions p where p.permission_id = p_permission_id and p.data_status = 1) then
    raise exception using errcode = 'AB040', message = 'Permission not found.';
  end if;

  insert into public.client_role_permissions (client_id, role_id, permission_id, is_allowed)
  values (v_ctx.o_client_id, p_role_id, p_permission_id, coalesce(p_is_allowed, false))
  on conflict (client_id, role_id, permission_id)
  do update set is_allowed = excluded.is_allowed, data_status = 1;
end;
$$;

-- Disables (cuts off the phone at once) or re-enables a staff user, within the plan's user limit.
create or replace function public.set_user_status(p_user_id integer, p_data_status integer)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_ctx    record;
  v_target public.users;
  v_full   boolean;
  v_max    integer;
begin
  select * into v_ctx from private.require_session();
  perform private.require_permission('users.manage');

  if p_data_status not in (0, 1) then
    raise exception using errcode = 'AB029', message = 'Invalid status.';
  end if;

  select u.* into v_target from public.users u
   where u.user_id = p_user_id and u.client_id = v_ctx.o_client_id
  for update;
  if not found then
    raise exception using errcode = 'AB040', message = 'User not found.';
  end if;
  if v_target.user_id = v_ctx.o_user_id then
    raise exception using errcode = 'AB010', message = 'You cannot change your own status.';
  end if;
  select r.is_full_access into v_full from public.roles r where r.role_id = v_target.role_id;
  if v_full then
    raise exception using errcode = 'AB010', message = 'The owner cannot be disabled here.';
  end if;

  if p_data_status = 1 and v_target.data_status = 0 then
    select l.max_users into v_max from public.licenses l where l.client_id = v_ctx.o_client_id;
    if (select count(*) from public.users u
         where u.client_id = v_ctx.o_client_id and u.data_status = 1) >= v_max then
      raise exception using errcode = 'AB030', message = 'Your plan''s user limit has been reached.';
    end if;
  end if;

  update public.users set data_status = p_data_status where user_id = p_user_id;

  if p_data_status = 0 then
    update public.devices set data_status = 0 where user_id = p_user_id and data_status = 1;  -- cut off now
  end if;
end;
$$;

-- Pre-checks for the add-staff-user Edge Function (runs as the caller, before the login is created).
create or replace function public.prepare_add_user(p_email text, p_role_id integer)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_ctx   record;
  v_email text := lower(trim(coalesce(p_email, '')));
  v_role  public.roles;
  v_max   integer;
begin
  select * into v_ctx from private.require_session();
  perform private.require_permission('users.manage');

  select r.* into v_role from public.roles r where r.role_id = p_role_id and r.data_status = 1;
  if not found or v_role.is_full_access then
    raise exception using errcode = 'AB010', message = 'Only staff users can be added here.';
  end if;

  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception using errcode = 'AB028', message = 'Email address is not valid.';
  end if;
  if exists (select 1 from public.users u where lower(u.email) = v_email)
     or exists (select 1 from auth.users au where lower(au.email) = v_email) then
    raise exception using errcode = 'AB031', message = 'This email is already registered.';
  end if;

  select l.max_users into v_max from public.licenses l where l.client_id = v_ctx.o_client_id;
  if (select count(*) from public.users u
       where u.client_id = v_ctx.o_client_id and u.data_status = 1) >= v_max then
    raise exception using errcode = 'AB030', message = 'Your plan''s user limit has been reached.';
  end if;

  return jsonb_build_object('client_id', v_ctx.o_client_id, 'role_code', v_role.role_code, 'email', v_email);
end;
$$;

-- Uploads queued warnings/errors (at most 50 per call; other levels are dropped).
create or replace function public.log_app_events(p_events jsonb)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_user_id   integer := private.current_user_id();
  v_client_id integer;
  v_device_id integer;
begin
  if v_user_id is null or jsonb_typeof(p_events) <> 'array' then
    return;
  end if;
  select u.client_id into v_client_id from public.users u where u.user_id = v_user_id;
  select d.device_id into v_device_id from public.devices d where d.user_id = v_user_id and d.data_status = 1;

  insert into public.app_events (client_id, user_id, device_id, level, event_code, message, context,
                                 app_version, occurred_at)
  select v_client_id, v_user_id, v_device_id,
         e ->> 'level',
         left(coalesce(e ->> 'event_code', 'unknown'), 64),
         left(coalesce(e ->> 'message', ''), 500),
         coalesce(e -> 'context', '{}'::jsonb),
         left(coalesce(e ->> 'app_version', ''), 32),
         coalesce((e ->> 'occurred_at')::timestamptz, now())
    from jsonb_array_elements(p_events) e
   where e ->> 'level' in ('warn', 'error')
   limit 50;
end;
$$;
