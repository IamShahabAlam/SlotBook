-- RLS on all 19 tables. Only select policies exist: writes happen only inside security definer RPCs owned by postgres.
-- Helpers are wrapped in (select ...) so Postgres evaluates them once per query, not once per row.

do $$
declare t text;
begin
  foreach t in array array[
    'roles', 'permissions', 'role_permissions', 'plans', 'booking_statuses', 'business_profiles',
    'clients', 'invoice_counters', 'client_role_permissions', 'booking_sessions', 'licenses',
    'resource_types', 'resources', 'app_admins', 'users', 'devices', 'bookings',
    'audit_logs', 'app_events'
  ] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end;
$$;

-- Lookups: readable by any signed-in user
create policy roles_read             on public.roles             for select to authenticated using (true);
create policy permissions_read       on public.permissions       for select to authenticated using (true);
create policy role_permissions_read  on public.role_permissions  for select to authenticated using (true);
create policy plans_read             on public.plans             for select to authenticated using (true);
create policy booking_statuses_read  on public.booking_statuses  for select to authenticated using (true);
create policy business_profiles_read on public.business_profiles for select to authenticated using (true);

-- Client data: own client (from the active phone session) or platform admin
create policy clients_read on public.clients for select to authenticated
  using (client_id = (select private.session_client_id()) or (select private.is_app_admin()));
create policy client_role_permissions_read on public.client_role_permissions for select to authenticated
  using (client_id = (select private.session_client_id()) or (select private.is_app_admin()));
create policy booking_sessions_read on public.booking_sessions for select to authenticated
  using (client_id = (select private.session_client_id()) or (select private.is_app_admin()));
create policy licenses_read on public.licenses for select to authenticated
  using (client_id = (select private.session_client_id()) or (select private.is_app_admin()));
create policy resource_types_read on public.resource_types for select to authenticated
  using (client_id = (select private.session_client_id()) or (select private.is_app_admin()));
create policy resources_read on public.resources for select to authenticated
  using (client_id = (select private.session_client_id()) or (select private.is_app_admin()));
create policy users_read on public.users for select to authenticated
  using (client_id = (select private.session_client_id()) or (select private.is_app_admin()));
create policy bookings_read on public.bookings for select to authenticated
  using (client_id = (select private.session_client_id()) or (select private.is_app_admin()));

-- Devices: a user sees their own device rows even after being replaced (so the old phone
-- receives the Realtime "you were signed out" change), admins see all.
create policy devices_read on public.devices for select to authenticated
  using (user_id = (select private.current_user_id()) or (select private.is_app_admin()));

-- Admin-only tables
create policy invoice_counters_read on public.invoice_counters for select to authenticated
  using ((select private.is_app_admin()));
create policy app_admins_read on public.app_admins for select to authenticated
  using ((select private.is_app_admin()));
create policy audit_logs_read on public.audit_logs for select to authenticated
  using ((select private.is_app_admin()));
create policy app_events_read on public.app_events for select to authenticated
  using ((select private.is_app_admin()));

-- Tables: no direct writes for app roles; anon reads nothing.
-- Fix: revoke ALL then grant select (spec listed privileges one by one), so Postgres 17's MAINTAIN
-- privilege (vacuum, lock table...) is removed too.
revoke all on all tables in schema public from anon, authenticated;
grant select on all tables in schema public to authenticated;

alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public grant select on tables to authenticated;

-- Functions: nothing callable unless granted explicitly (20261103001700_grants.sql re-applies this at the end,
-- because a per-schema default can't remove PUBLIC's built-in execute on new functions).
revoke execute on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
revoke execute on all functions in schema private from public, anon, authenticated;

-- RLS policies call these as the querying role
grant usage on schema private to authenticated;
grant execute on function private.session_client_id(), private.current_user_id(), private.is_app_admin()
  to authenticated;
