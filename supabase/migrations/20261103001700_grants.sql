-- Execute grants on callable RPCs. Runs last, after every function exists. Add each new public function here.

-- Fix: re-revoke first (spec only revoked in the RLS migration). Postgres gives PUBLIC execute on every new
-- function, and the per-schema default privileges there can't remove that, so without this anon could call every RPC.
revoke execute on all functions in schema public from public, anon, authenticated;
revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.session_client_id(), private.current_user_id(), private.is_app_admin()
  to authenticated;

grant execute on function public.get_app_access(text) to anon, authenticated;
grant execute on function
  public.start_session(text, text, text, text, text, text, boolean),
  public.sign_out_device(),
  public.get_client_bundle(text),
  public.create_booking(uuid, integer, date, integer, integer, integer, text, text, text, text, integer, integer, integer),
  public.update_booking(integer, timestamptz, integer, date, integer, integer, integer, text, text, text, text, integer, integer, integer),
  public.mark_booking_paid(integer),
  public.cancel_booking(integer, text, boolean),
  public.update_hourly_rate(integer, integer),
  public.update_client_settings(text),
  public.set_role_permission(integer, integer, boolean),
  public.set_user_status(integer, integer),
  public.prepare_add_user(text, integer),
  public.log_app_events(jsonb),
  public.admin_create_client(jsonb),
  public.admin_add_user(integer, text, text, text)
  to authenticated;

-- The Edge Function calls admin_add_user with the service key
grant execute on function public.admin_create_client(jsonb), public.admin_add_user(integer, text, text, text)
  to service_role;
