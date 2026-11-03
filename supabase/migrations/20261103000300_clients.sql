-- Client setup: one row per business plus its counter, rights, sessions, licence and catalogue.
-- Composite foreign keys stop a resource (or booking) from pointing at another client's type (or resource).

create table public.clients (
  client_id                integer generated always as identity primary key,
  client_code              text not null unique check (client_code ~ '^[a-z0-9_]+$'),  -- = Flutter flavor
  name                     text not null,
  tagline                  text,
  address                  text,
  phone                    text,
  logo_path                text,                        -- Storage path in bucket client-assets, e.g. '12/logo.png'
  business_profile_id      integer not null references public.business_profiles (business_profile_id),
  timezone                 text not null default 'Asia/Karachi',
  currency_symbol          text not null default 'Rs',
  country_code             text not null default '92',
  terms                    jsonb not null default '{}', -- effective Terms (profile defaults merged with overrides)
  -- effective booking policy
  slot_step_minutes        smallint not null check (slot_step_minutes in (15, 30, 60)),
  min_duration_minutes     smallint not null check (min_duration_minutes > 0),
  max_duration_minutes     smallint not null check (max_duration_minutes <= 1440),
  default_duration_minutes smallint not null,
  open_start_minute        smallint check (open_start_minute between 0 and 1439),
  open_end_minute          smallint check (open_end_minute between 1 and 2880),   -- may pass midnight
  offers_full_day          boolean not null default false,
  -- pricing and features
  pricing_mode             smallint not null default 1 check (pricing_mode in (1, 2)),
  allow_discount           boolean not null default true,
  show_entry_pass          boolean not null default true,
  data_status              smallint not null default 1 check (data_status in (0, 1)),
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  check ((open_start_minute is null) = (open_end_minute is null)),
  check (open_end_minute is null or open_end_minute > open_start_minute),
  check (min_duration_minutes <= default_duration_minutes
         and default_duration_minutes <= max_duration_minutes)
);

create table public.invoice_counters (
  invoice_counter_id  integer generated always as identity primary key,
  client_id           integer not null unique references public.clients (client_id),
  last_invoice_number integer not null default 0 check (last_invoice_number >= 0),
  data_status         smallint not null default 1 check (data_status in (0, 1)),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create table public.client_role_permissions (
  client_role_permission_id integer generated always as identity primary key,
  client_id      integer not null references public.clients (client_id),
  role_id        integer not null references public.roles (role_id),
  permission_id  integer not null references public.permissions (permission_id),
  is_allowed     boolean not null,
  data_status    smallint not null default 1 check (data_status in (0, 1)),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (client_id, role_id, permission_id)
);

create table public.booking_sessions (
  booking_session_id integer generated always as identity primary key,
  client_id      integer not null references public.clients (client_id),
  label          text not null,                          -- 'Lunch'
  start_minute   smallint not null check (start_minute between 0 and 1439),
  end_minute     smallint not null check (end_minute <= 2880),
  sort_order     smallint not null default 0,
  data_status    smallint not null default 1 check (data_status in (0, 1)),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (end_minute > start_minute)
);
create index booking_sessions_client on public.booking_sessions (client_id);

create table public.licenses (
  license_id              integer generated always as identity primary key,
  client_id               integer not null unique references public.clients (client_id),
  plan_id                 integer not null references public.plans (plan_id),
  is_app_enable           boolean not null default true,      -- Gist: IsAppEnable
  app_disable_after_date  date,                               -- Gist: AppDisableAfterDate
  max_users               integer not null check (max_users >= 1),
  notes                   text not null default '',
  updated_by_app_admin_id integer,                            -- FK added after app_admins exists (people migration)
  data_status             smallint not null default 1 check (data_status in (0, 1)),  -- Gist: DataEntryStatus
  created_at              timestamptz not null default now(),                         -- Gist: DataEntryDate
  updated_at              timestamptz not null default now()                          -- Gist: LastUpdateDate
);

create table public.resource_types (
  resource_type_id integer generated always as identity primary key,
  client_id      integer not null references public.clients (client_id),
  name           text not null,                          -- 'Indoor Cricket'
  short_name     text not null,                          -- 'Cricket'
  icon_key       text not null,                          -- mapped to IconData in Dart
  tone           text not null check (tone in ('emerald', 'blue', 'violet', 'orange')),
  hourly_rate    integer check (hourly_rate is null or hourly_rate between 1 and 1000000),  -- null for manual pricing
  emoji          text not null default '',
  sort_order     smallint not null default 0,
  data_status    smallint not null default 1 check (data_status in (0, 1)),  -- 0 = hidden from forms; old bookings still show
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (client_id, resource_type_id)                   -- target for composite FK
);

create table public.resources (
  resource_id      integer generated always as identity primary key,
  client_id        integer not null references public.clients (client_id),
  resource_type_id integer not null,
  name             text not null,                        -- 'Pitch 1'
  description      text not null default '',
  sort_order       smallint not null default 0,
  data_status      smallint not null default 1 check (data_status in (0, 1)),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  foreign key (client_id, resource_type_id) references public.resource_types (client_id, resource_type_id),
  unique (client_id, resource_id)                        -- target for composite FK from bookings
);
create index resources_type on public.resources (resource_type_id);
