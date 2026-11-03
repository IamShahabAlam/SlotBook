-- Admin RPCs (SQL editor, service key, or an app admin with MFA): onboard a client, link an auth user to it.

-- Creates a client with its counter, licence, own copy of the default rights, sessions and catalogue.
-- Omitted policy/pricing/feature fields come from the business profile; terms overrides win over profile terms.
create or replace function public.admin_create_client(p_payload jsonb)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_profile    public.business_profiles;
  v_plan       public.plans;
  v_client_id  integer;
  v_type       jsonb;
  v_res        jsonb;
  v_sess       jsonb;
  v_type_id    integer;
  v_trial_days integer := (p_payload ->> 'trial_days')::integer;
begin
  perform private.require_admin();

  select bp.* into v_profile from public.business_profiles bp
   where bp.profile_code = p_payload ->> 'business_profile_code' and bp.data_status = 1;
  if not found then raise exception 'Unknown business_profile_code'; end if;

  select pl.* into v_plan from public.plans pl
   where pl.plan_code = coalesce(p_payload ->> 'plan_code', 'trial') and pl.data_status = 1;
  if not found then raise exception 'Unknown plan_code'; end if;

  insert into public.clients (
    client_code, name, tagline, address, phone, logo_path, business_profile_id,
    timezone, currency_symbol, country_code, terms,
    slot_step_minutes, min_duration_minutes, max_duration_minutes, default_duration_minutes,
    open_start_minute, open_end_minute, offers_full_day,
    pricing_mode, allow_discount, show_entry_pass)
  values (
    p_payload ->> 'client_code', p_payload ->> 'name', p_payload ->> 'tagline',
    p_payload ->> 'address', p_payload ->> 'phone', p_payload ->> 'logo_path',
    v_profile.business_profile_id,
    coalesce(p_payload ->> 'timezone', 'Asia/Karachi'),
    coalesce(p_payload ->> 'currency_symbol', 'Rs'),
    coalesce(p_payload ->> 'country_code', '92'),
    v_profile.default_terms || coalesce(p_payload -> 'terms', '{}'::jsonb),     -- overrides win
    coalesce((p_payload ->> 'slot_step_minutes')::smallint,        v_profile.slot_step_minutes),
    coalesce((p_payload ->> 'min_duration_minutes')::smallint,     v_profile.min_duration_minutes),
    coalesce((p_payload ->> 'max_duration_minutes')::smallint,     v_profile.max_duration_minutes),
    coalesce((p_payload ->> 'default_duration_minutes')::smallint, v_profile.default_duration_minutes),
    case when p_payload ? 'open_start_minute' then (p_payload ->> 'open_start_minute')::smallint
         else v_profile.open_start_minute end,
    case when p_payload ? 'open_end_minute' then (p_payload ->> 'open_end_minute')::smallint
         else v_profile.open_end_minute end,
    coalesce((p_payload ->> 'offers_full_day')::boolean, v_profile.offers_full_day),
    coalesce((p_payload ->> 'pricing_mode')::smallint,   v_profile.pricing_mode),
    coalesce((p_payload ->> 'allow_discount')::boolean,  v_profile.allow_discount),
    coalesce((p_payload ->> 'show_entry_pass')::boolean, v_profile.show_entry_pass))
  returning client_id into v_client_id;

  insert into public.invoice_counters (client_id) values (v_client_id);

  -- trial: enabled until a date (Gist semantics: IsAppEnable=false + AppDisableAfterDate)
  insert into public.licenses (client_id, plan_id, is_app_enable, app_disable_after_date, max_users)
  values (v_client_id, v_plan.plan_id,
          v_trial_days is null,
          case when v_trial_days is null then null else current_date + v_trial_days end,
          v_plan.max_users);

  -- this client's own copy of the default rights
  insert into public.client_role_permissions (client_id, role_id, permission_id, is_allowed)
  select v_client_id, rp.role_id, rp.permission_id, rp.is_allowed
    from public.role_permissions rp
    join public.roles r on r.role_id = rp.role_id and not r.is_full_access
   where rp.data_status = 1;

  for v_sess in
    select value from jsonb_array_elements(coalesce(p_payload -> 'booking_sessions', v_profile.default_sessions))
  loop
    insert into public.booking_sessions (client_id, label, start_minute, end_minute, sort_order)
    values (v_client_id, v_sess ->> 'label', (v_sess ->> 'start_minute')::smallint,
            (v_sess ->> 'end_minute')::smallint, coalesce((v_sess ->> 'sort_order')::smallint, 0));
  end loop;

  for v_type in select value from jsonb_array_elements(coalesce(p_payload -> 'resource_types', '[]'::jsonb))
  loop
    insert into public.resource_types (client_id, name, short_name, icon_key, tone, hourly_rate, emoji, sort_order)
    values (v_client_id, v_type ->> 'name', coalesce(v_type ->> 'short_name', v_type ->> 'name'),
            v_type ->> 'icon_key', v_type ->> 'tone', (v_type ->> 'hourly_rate')::integer,
            coalesce(v_type ->> 'emoji', ''), coalesce((v_type ->> 'sort_order')::smallint, 0))
    returning resource_type_id into v_type_id;

    for v_res in select value from jsonb_array_elements(coalesce(v_type -> 'resources', '[]'::jsonb))
    loop
      insert into public.resources (client_id, resource_type_id, name, description, sort_order)
      values (v_client_id, v_type_id, v_res ->> 'name', coalesce(v_res ->> 'description', ''),
              coalesce((v_res ->> 'sort_order')::smallint, 0));
    end loop;
  end loop;

  return v_client_id;
end;
$$;

-- Links an existing auth user (created in the dashboard or by the Edge Function) to a client and role.
create or replace function public.admin_add_user(
  p_client_id integer, p_email text, p_full_name text, p_role_code text)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_email   text := lower(trim(p_email));
  v_auth_id uuid;
  v_role_id integer;
  v_max     integer;
  v_user_id integer;
begin
  perform private.require_admin();

  select au.id into v_auth_id from auth.users au where lower(au.email) = v_email;
  if v_auth_id is null then
    raise exception 'Create the auth user first (Authentication → Add user, auto-confirm).';
  end if;

  select r.role_id into v_role_id from public.roles r where r.role_code = p_role_code and r.data_status = 1;
  if v_role_id is null then raise exception 'Unknown role_code'; end if;

  select l.max_users into v_max from public.licenses l where l.client_id = p_client_id;
  if (select count(*) from public.users u where u.client_id = p_client_id and u.data_status = 1) >= v_max then
    raise exception using errcode = 'AB030', message = 'User limit reached for this client''s plan.';
  end if;

  insert into public.users (auth_user_id, client_id, role_id, full_name, email)
  values (v_auth_id, p_client_id, v_role_id, trim(p_full_name), v_email)
  returning user_id into v_user_id;

  return v_user_id;
end;
$$;
