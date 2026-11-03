-- Grants (§9.3): no direct writes for app roles, anon reads nothing, only granted RPCs are callable.
begin;
\ir _setup.psql
select plan(14);

select is((select array_agg(c.relname::text) from pg_class c
            where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v')
              and (has_table_privilege('anon', c.oid, 'select') or has_table_privilege('anon', c.oid, 'insert')
                   or has_table_privilege('anon', c.oid, 'update') or has_table_privilege('anon', c.oid, 'delete'))),
          null, 'anon has no table privileges');

select is((select array_agg(c.relname::text) from pg_class c
            where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v')
              and (has_table_privilege('authenticated', c.oid, 'insert') or has_table_privilege('authenticated', c.oid, 'update')
                   or has_table_privilege('authenticated', c.oid, 'delete') or has_table_privilege('authenticated', c.oid, 'truncate')
                   or has_table_privilege('authenticated', c.oid, 'maintain')
                   or not has_table_privilege('authenticated', c.oid, 'select'))),
          null, 'authenticated can only select, on every table and view');

select is((select array_agg(p.proname::text) from pg_proc p
            where p.pronamespace = 'public'::regnamespace and has_function_privilege('anon', p.oid, 'execute')),
          array['get_app_access'], 'anon can execute only get_app_access');

select is((select array_agg(p.proname::text order by p.proname) from pg_proc p
            where p.pronamespace = 'public'::regnamespace and has_function_privilege('authenticated', p.oid, 'execute')),
          array['admin_add_user', 'admin_create_client', 'cancel_booking', 'create_booking', 'get_app_access',
                'get_client_bundle', 'log_app_events', 'mark_booking_paid', 'prepare_add_user', 'set_role_permission',
                'set_user_status', 'sign_out_device', 'start_session', 'update_booking', 'update_client_settings',
                'update_hourly_rate'],
          'authenticated can execute exactly the documented RPCs');

select is((select array_agg(p.proname::text order by p.proname) from pg_proc p
            where p.pronamespace = 'private'::regnamespace and has_function_privilege('authenticated', p.oid, 'execute')),
          array['current_user_id', 'is_app_admin', 'session_client_id'],
          'authenticated can execute only the three RLS helpers in private');

-- as a signed-in owner on the active phone
select tests.login('owner_a@test.dev');
select throws_ok($$insert into public.roles (role_code, name) values ('x', 'x')$$, '42501', null,
                 'direct insert is refused');
select throws_ok($$update public.clients set name = 'hacked'$$, '42501', null, 'direct update is refused');
select throws_ok($$delete from public.bookings$$, '42501', null, 'direct delete is refused');
select is((select count(*)::int from public.clients), 1, 'select works through RLS');

-- as anon (before sign-in)
select tests.as_anon();
select throws_ok($$select * from public.clients$$, '42501', null, 'anon cannot read tables');
select throws_ok($$select * from public.booking_details$$, '42501', null, 'anon cannot read the bookings view');
select throws_ok($$select public.create_booking(gen_random_uuid(), 1, current_date, 600, 660, null,
                                                'x', '03001234567', '', '', null, 0, 0)$$,
                 '42501', null, 'anon cannot call write RPCs');
select is((public.get_app_access('test_a') ->> 'found')::boolean, true, 'anon can call get_app_access');
select tests.logout();

select ok(not has_function_privilege('anon', 'public.admin_create_client(jsonb)', 'execute'),
          'anon cannot call admin RPCs');

select * from finish();
rollback;
