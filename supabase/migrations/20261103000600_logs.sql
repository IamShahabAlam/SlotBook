-- Append-only logs: audit_logs (field diffs written by triggers) and app_events (warnings/errors from the app).

create table public.audit_logs (
  audit_log_id    integer generated always as identity primary key,
  client_id       integer references public.clients (client_id),
  table_name      text not null,
  record_id       integer not null,
  action          text not null check (action in ('insert', 'update')),
  changed_fields  jsonb not null default '{}',   -- {"advance_paid": [3000, 10000]}; '{}' for inserts
  user_id         integer references public.users (user_id),
  app_admin_id    integer references public.app_admins (app_admin_id),
  data_status     smallint not null default 1 check (data_status in (0, 1)),
  created_at      timestamptz not null default now()
);
create index audit_logs_client_created on public.audit_logs (client_id, created_at);
create index audit_logs_record on public.audit_logs (table_name, record_id);

create table public.app_events (
  app_event_id    integer generated always as identity primary key,
  client_id       integer references public.clients (client_id),
  user_id         integer references public.users (user_id),
  device_id       integer references public.devices (device_id),
  level           text not null check (level in ('warn', 'error')),
  event_code      text not null,
  message         text not null default '',
  context         jsonb not null default '{}',
  app_version     text not null default '',
  occurred_at     timestamptz not null,          -- phone time
  data_status     smallint not null default 1 check (data_status in (0, 1)),
  created_at      timestamptz not null default now()
);
create index app_events_created on public.app_events (created_at);
create index app_events_client_created on public.app_events (client_id, created_at);
