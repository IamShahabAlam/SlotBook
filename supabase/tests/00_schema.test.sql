-- Schema conventions (§0.2, §5) and the fixed lookup ids Dart mirrors (Appendix B).
begin;
\ir _setup.psql
select plan(16);

select tables_are('public', array[
  'roles', 'permissions', 'role_permissions', 'plans', 'booking_statuses', 'business_profiles',
  'clients', 'invoice_counters', 'client_role_permissions', 'booking_sessions', 'licenses',
  'resource_types', 'resources', 'app_admins', 'users', 'devices', 'bookings', 'audit_logs', 'app_events'],
  'exactly the 19 tables exist');

select is((select count(*)::int from pg_class c
            where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relrowsecurity),
          19, 'RLS is enabled on all 19 tables');

select is((select array_agg(c.relname::text order by c.relname) from pg_class c
            join pg_constraint k on k.conrelid = c.oid and k.contype = 'p'
            join pg_attribute a on a.attrelid = c.oid and a.attnum = k.conkey[1]
           where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
             and (array_length(k.conkey, 1) <> 1 or a.atttypid <> 'integer'::regtype or a.attidentity = ''
                  or a.attname not like '%\_id')),
          null, 'every table has a single integer identity primary key named <singular>_id');

select is((select array_agg(t.table_name::text) from information_schema.tables t
            where t.table_schema = 'public' and t.table_type = 'BASE TABLE'
              and not exists (select 1 from information_schema.columns c
                               where c.table_schema = 'public' and c.table_name = t.table_name
                                 and c.column_name = 'data_status' and c.data_type = 'smallint' and c.is_nullable = 'NO')),
          null, 'every table has data_status smallint not null');

select is((select count(*)::int from pg_constraint k
            where k.connamespace = 'public'::regnamespace and k.contype = 'c'
              and pg_get_constraintdef(k.oid) like '%data_status = ANY (ARRAY[0, 1])%'),
          19, 'every data_status is limited to 0 and 1 by a CHECK');

select is((select array_agg(t.table_name::text) from information_schema.tables t
            where t.table_schema = 'public' and t.table_type = 'BASE TABLE'
              and not exists (select 1 from information_schema.columns c
                               where c.table_schema = 'public' and c.table_name = t.table_name
                                 and c.column_name = 'created_at' and c.data_type = 'timestamp with time zone')),
          null, 'every table has created_at timestamptz');

select is((select array_agg(t.table_name::text order by t.table_name) from information_schema.tables t
            where t.table_schema = 'public' and t.table_type = 'BASE TABLE'
              and not exists (select 1 from information_schema.columns c
                               where c.table_schema = 'public' and c.table_name = t.table_name
                                 and c.column_name = 'updated_at')),
          array['app_events', 'audit_logs'], 'only the two log tables have no updated_at');

select is((select count(*)::int from pg_trigger g join pg_class c on c.oid = g.tgrelid
            where c.relnamespace = 'public'::regnamespace and g.tgname = 'set_updated_at'),
          17, 'every mutable table has the set_updated_at trigger');

select is((select count(*)::int from pg_type t where t.typnamespace = 'public'::regnamespace and t.typtype = 'e'),
          0, 'no Postgres ENUM types');

select col_is_pk('public', 'bookings', 'booking_id', 'bookings keyed by booking_id');
select ok(exists (select 1 from pg_constraint where conname = 'bookings_no_overlap' and contype = 'x'),
          'the no-overlap exclusion constraint exists');

select results_eq($$select role_id, role_code, is_full_access from public.roles order by 1$$,
                  $$values (1, 'owner', true), (2, 'staff', false)$$, 'role ids match RoleIds');
select results_eq($$select permission_id, permission_code from public.permissions order by 1$$,
                  $$values (1, 'booking.create'), (2, 'booking.edit'), (3, 'booking.mark_paid'), (4, 'booking.cancel'),
                           (5, 'revenue.view'), (6, 'settings.edit'), (7, 'users.manage')$$,
                  'permission ids match PermissionIds');
select results_eq($$select booking_status_id, status_code from public.booking_statuses order by 1$$,
                  $$values (1, 'pending'), (2, 'paid'), (3, 'cancelled'), (4, 'refunded')$$,
                  'booking status ids match BookingStatusIds');
select results_eq($$select plan_id, plan_code from public.plans order by 1$$,
                  $$values (1, 'trial'), (2, 'monthly'), (3, 'yearly'), (4, 'lifetime')$$, 'plan ids match PlanIds');
select results_eq(
  $$select business_profile_id, profile_code, slot_step_minutes::int, min_duration_minutes::int,
           default_duration_minutes::int, offers_full_day, pricing_mode::int, jsonb_array_length(default_sessions),
           default_terms ->> 'resource'
      from public.business_profiles order by 1$$,
  $$values (1, 'sports_venue',   30, 30,  60, false, 1, 0, 'Court'),
           (2, 'space_rental',   60, 60, 120, true,  1, 0, 'Space'),
           (3, 'event_venue',    60, 60, 240, false, 2, 3, 'Hall'),
           (4, 'vehicle_rental', 60, 60, 120, false, 1, 0, 'Vehicle')$$,
  'business profiles match profiles.dart');

select * from finish();
rollback;
