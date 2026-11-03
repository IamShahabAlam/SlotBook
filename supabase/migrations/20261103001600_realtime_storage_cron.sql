-- Realtime publication (RLS-filtered per subscriber), the public logo bucket, and log retention.

alter publication supabase_realtime add table
  public.bookings, public.clients, public.resource_types, public.resources,
  public.booking_sessions, public.client_role_permissions, public.devices, public.licenses, public.users;

insert into storage.buckets (id, name, public)
values ('client-assets', 'client-assets', true)
on conflict (id) do nothing;
-- No storage policies for app users: only the dashboard / service key uploads logos.

select cron.schedule('purge-app-events', '0 22 * * *',   -- 03:00 Pakistan time
  $$delete from public.app_events where created_at < now() - interval '90 days'$$);
