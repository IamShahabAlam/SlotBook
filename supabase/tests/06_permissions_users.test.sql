-- Roles and rights per client, staff management, user limits, app events, platform admins (§11.5, §14).
begin;
\ir _setup.psql
select plan(28);

select tests.login('owner_a@test.dev');
select tests.keep('b', tests.book(tests.resource_id('test_a', 'A1'), tests.today() + 5, 600, 660));

-- staff defaults
select tests.login('staff_a@test.dev');
select lives_ok(format($$select tests.book(%s, tests.today() + 6, 600, 660)$$, tests.resource_id('test_a', 'A1')),
                'staff can create bookings');
select throws_ok(format($$select public.cancel_booking(%s, 'x', false)$$, tests.got_id('b')), 'AB010', null,
                 'staff cannot cancel by default');
select throws_ok(format('select public.update_hourly_rate(%s, 100)', tests.type_id('test_a', 'Cricket')), 'AB010', null,
                 'staff cannot change rates');
select throws_ok($$select public.update_client_settings('$')$$, 'AB010', null, 'staff cannot change settings');
select throws_ok('select public.set_role_permission(2, 4, true)', 'AB010', null, 'staff cannot change rights');

-- the owner changes this client's staff rights
select tests.login('owner_a@test.dev');
select lives_ok('select public.set_role_permission(2, 4, true)', 'owner allows staff to cancel');
select throws_ok('select public.set_role_permission(1, 4, false)', 'AB010', 'Owner rights cannot be changed.',
                 'owner rights are fixed');
select tests.login('staff_a@test.dev');
select is(public.cancel_booking(tests.got_id('b'), 'Rain', false) ->> 'booking_status_code', 'cancelled',
          'staff can now cancel');
select ok(public.get_client_bundle(null) -> 'permissions' ? 'booking.cancel', 'the bundle shows the new right');
select tests.logout();
select is((select is_allowed from public.client_role_permissions
            where client_id = tests.client_id('test_b') and role_id = 2 and permission_id = 4),
          false, 'another client''s staff rights are untouched');

-- disabling and re-enabling staff
select tests.login('owner_a@test.dev');
select throws_ok(format('select public.set_user_status(%s, 0)', tests.user_id('owner_a@test.dev')), 'AB010', null,
                 'you cannot disable yourself');
select lives_ok(format('select public.set_user_status(%s, 0)', tests.user_id('staff_a@test.dev')), 'owner disables staff');
select tests.login('staff_a@test.dev');
select is((select count(*)::int from public.clients), 0, 'a disabled user reads nothing');
select throws_ok('select public.get_client_bundle(null)', 'AB001', null, 'a disabled user is signed out');
select is((select count(*)::int from public.devices where data_status = 1), 0, 'their phone was cut off');

-- user limit (monthly plan: 3 active users)
select tests.logout();
select tests.add_user('test_a', 'staff2_a@test.dev', 'staff');
select tests.add_user('test_a', 'staff3_a@test.dev', 'staff');
select throws_ok($$select tests.add_user('test_a', 'staff4_a@test.dev', 'staff')$$, 'AB030', null,
                 'admin_add_user respects the plan''s user limit');
select tests.login('owner_a@test.dev');
select throws_ok(format('select public.set_user_status(%s, 1)', tests.user_id('staff_a@test.dev')), 'AB030', null,
                 're-enabling is refused at the limit');
select throws_ok($$select public.prepare_add_user('new@test.dev', 2)$$, 'AB030', null,
                 'adding staff is refused at the limit');
select lives_ok(format('select public.set_user_status(%s, 0)', tests.user_id('staff3_a@test.dev')), 'free a seat');
select is(public.prepare_add_user(' New@Test.dev ', 2) ->> 'email', 'new@test.dev', 'prepare_add_user passes with a free seat');
select throws_ok($$select public.prepare_add_user('owner_b@test.dev', 2)$$, 'AB031', null, 'an email already in use');
select throws_ok($$select public.prepare_add_user('new@test.dev', 1)$$, 'AB010', null, 'owners cannot be added here');
select throws_ok($$select public.prepare_add_user('bad email', 2)$$, 'AB028', null, 'email must be valid');

-- app events: warnings and errors only, readable by admins only
select lives_ok($$select public.log_app_events('[
    {"level": "warn",  "event_code": "booking_conflict", "occurred_at": "2026-11-03T10:00:00Z"},
    {"level": "info",  "event_code": "routine"},
    {"level": "error", "event_code": "rpc_error", "context": {"fn": "create_booking"}}]')$$, 'events upload');
select is((select count(*)::int from public.app_events), 0, 'client users cannot read app events');

-- platform admin: reads every client only with MFA (aal2)
select tests.logout();
insert into auth.users (id, email) values (tests.uid('admin@devcat.dev'), 'admin@devcat.dev');
insert into public.app_admins (auth_user_id, full_name, email) values (tests.uid('admin@devcat.dev'), 'Shahab', 'admin@devcat.dev');
select is((select array_agg(event_code order by event_code) from public.app_events), array['booking_conflict', 'rpc_error'],
          'only warn and error events were stored');
select tests.login('admin@devcat.dev', 'admin', 'aal1');
select is((select count(*)::int from public.clients), 0, 'an admin without MFA sees nothing');
select tests.login('admin@devcat.dev', 'admin', 'aal2');
select is((select count(*)::int from public.clients where client_code in ('test_a', 'test_b')), 2,
          'an admin with MFA sees every client');

select * from finish();
rollback;
