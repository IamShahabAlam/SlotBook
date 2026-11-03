-- People: platform admins, client users (owner/staff) and the phones they sign in on (one active per user).

create table public.app_admins (
  app_admin_id   integer generated always as identity primary key,
  auth_user_id   uuid not null unique references auth.users (id),
  full_name      text not null,
  email          text not null,
  data_status    smallint not null default 1 check (data_status in (0, 1)),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

alter table public.licenses
  add constraint licenses_updated_by_fk
  foreign key (updated_by_app_admin_id) references public.app_admins (app_admin_id);

create table public.users (
  user_id        integer generated always as identity primary key,
  auth_user_id   uuid not null unique references auth.users (id),
  client_id      integer not null references public.clients (client_id),
  role_id        integer not null references public.roles (role_id),
  full_name      text not null,
  email          text not null,
  phone          text not null default '',
  data_status    smallint not null default 1 check (data_status in (0, 1)),  -- 0 = disabled (cannot sign in)
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index users_client on public.users (client_id);

create table public.devices (
  device_id          integer generated always as identity primary key,
  user_id            integer not null references public.users (user_id),
  client_id          integer not null references public.clients (client_id),
  auth_session_id    uuid not null,              -- JWT claim session_id of this phone's login
  device_uid         text not null,              -- random UUID kept in the phone's secure storage
  platform_device_id text not null default '',   -- optional hint: ANDROID_ID / identifierForVendor
  device_name        text not null default '',   -- 'Samsung SM-A546E'
  platform           text not null check (platform in ('android', 'ios')),
  app_version        text not null default '',
  last_seen_at       timestamptz not null default now(),
  data_status        smallint not null default 1 check (data_status in (0, 1)),  -- 1 = the active phone
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create unique index devices_one_active_per_user on public.devices (user_id) where data_status = 1;
create index devices_session on public.devices (auth_session_id) where data_status = 1;
