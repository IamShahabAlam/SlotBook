-- Triggers: updated_at everywhere, booking derived values + automatic status, booking guard, audit diffs.

do $$
declare
  t text;
begin
  foreach t in array array[
    'roles', 'permissions', 'role_permissions', 'plans', 'booking_statuses', 'business_profiles',
    'clients', 'invoice_counters', 'client_role_permissions', 'booking_sessions', 'licenses',
    'resource_types', 'resources', 'app_admins', 'users', 'devices', 'bookings'
  ] loop
    execute format(
      'create trigger set_updated_at before update on public.%I
         for each row execute function private.set_updated_at()', t);
  end loop;
end;
$$;

-- Status: 1 pending, 2 paid, 3 cancelled (advance kept or none), 4 refunded. "Completed" is derived from ends_at.
create or replace function private.bookings_derive()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tz text;
begin
  select c.timezone into v_tz from public.clients c where c.client_id = new.client_id;

  new.duration_minutes := new.end_minute - new.start_minute;
  new.starts_at := (new.booking_date::timestamp + make_interval(mins => new.start_minute)) at time zone v_tz;
  new.ends_at   := (new.booking_date::timestamp + make_interval(mins => new.end_minute))   at time zone v_tz;

  new.booking_status_id := case
    when new.cancelled_at is not null and new.advance_returned and new.advance_paid > 0 then 4  -- refunded
    when new.cancelled_at is not null then 3                                                     -- cancelled
    when new.balance_settled_at is not null
      or new.advance_paid >= new.total_fee - new.discount then 2                                 -- paid
    else 1                                                                                       -- pending
  end;
  return new;
end;
$$;

create trigger bookings_derive
  before insert or update on public.bookings
  for each row execute function private.bookings_derive();

-- Defence in depth: identity fields never change; cancelled bookings are frozen.
create or replace function private.bookings_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.client_id <> old.client_id
     or new.request_uid <> old.request_uid
     or new.invoice_number <> old.invoice_number
     or new.created_at <> old.created_at
     or new.created_by_user_id <> old.created_by_user_id then
    raise exception using errcode = 'AB024', message = 'Booking identity fields cannot change.';
  end if;

  if old.cancelled_at is not null and (
       new.cancelled_at is distinct from old.cancelled_at
       or new.resource_id <> old.resource_id
       or new.booking_date <> old.booking_date
       or new.start_minute <> old.start_minute
       or new.end_minute <> old.end_minute
       or new.total_fee <> old.total_fee
       or new.discount <> old.discount
       or new.advance_paid <> old.advance_paid) then
    raise exception using errcode = 'AB024', message = 'Cancelled bookings cannot be changed.';
  end if;
  return new;
end;
$$;

create trigger bookings_guard
  before update on public.bookings
  for each row execute function private.bookings_guard();

-- Compact audit: '{}' on insert (the row is the record), only changed fields on update, nothing if no real change.
create or replace function private.write_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_new  jsonb := to_jsonb(new);
  v_old  jsonb;
  v_diff jsonb := '{}'::jsonb;
  v_key  text;
begin
  if tg_op = 'UPDATE' then
    v_old := to_jsonb(old);
    for v_key in select jsonb_object_keys(v_new) loop
      if v_key not in ('updated_at', 'starts_at', 'ends_at', 'duration_minutes', 'invoice_no',
                       'last_seen_at', 'app_version')
         and (v_new -> v_key) is distinct from (v_old -> v_key) then
        v_diff := v_diff || jsonb_build_object(v_key, jsonb_build_array(v_old -> v_key, v_new -> v_key));
      end if;
    end loop;
    if v_diff = '{}'::jsonb then
      return new;                       -- nothing meaningful changed
    end if;
  end if;

  insert into public.audit_logs (client_id, table_name, record_id, action, changed_fields, user_id, app_admin_id)
  values ((v_new ->> 'client_id')::integer,
          tg_table_name,
          (v_new ->> tg_argv[0])::integer,
          lower(tg_op),
          v_diff,
          private.current_user_id(),
          private.current_app_admin_id());
  return new;
end;
$$;

-- Not audited: lookups (rare, admin-managed), invoice_counters (every booking insert already records it), logs.
create trigger write_audit after insert or update on public.bookings
  for each row execute function private.write_audit('booking_id');
create trigger write_audit after insert or update on public.clients
  for each row execute function private.write_audit('client_id');
create trigger write_audit after insert or update on public.licenses
  for each row execute function private.write_audit('license_id');
create trigger write_audit after insert or update on public.booking_sessions
  for each row execute function private.write_audit('booking_session_id');
create trigger write_audit after insert or update on public.resource_types
  for each row execute function private.write_audit('resource_type_id');
create trigger write_audit after insert or update on public.resources
  for each row execute function private.write_audit('resource_id');
create trigger write_audit after insert or update on public.users
  for each row execute function private.write_audit('user_id');
create trigger write_audit after insert or update on public.devices
  for each row execute function private.write_audit('device_id');
create trigger write_audit after insert or update on public.client_role_permissions
  for each row execute function private.write_audit('client_role_permission_id');
