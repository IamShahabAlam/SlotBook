-- Client isolation (RLS) and the one-active-phone-per-user session rules (§9.2, §13).
begin;
\ir _setup.psql
select plan(32);

-- a booking for each client
select tests.login('owner_a@test.dev');
select tests.keep('a1', tests.book(tests.resource_id('test_a', 'A1'), tests.today() + 5, 600, 660));
select tests.login('owner_b@test.dev');
select tests.keep('b1', tests.book(tests.resource_id('test_b', 'B1'), tests.today() + 5, 600, 660));

-- Isolation: owner A sees nothing of client B, in any table or the view
select tests.login('owner_a@test.dev');
select is((select array_agg(client_code) from public.clients), array['test_a'], 'owner A sees only client A');
select is((select count(*)::int from public.client_role_permissions where client_id = tests.client_id('test_b')) +
          (select count(*)::int from public.booking_sessions where client_id = tests.client_id('test_b')) +
          (select count(*)::int from public.licenses where client_id = tests.client_id('test_b')) +
          (select count(*)::int from public.resource_types where client_id = tests.client_id('test_b')) +
          (select count(*)::int from public.resources where client_id = tests.client_id('test_b')) +
          (select count(*)::int from public.users where client_id = tests.client_id('test_b')) +
          (select count(*)::int from public.devices where client_id = tests.client_id('test_b')) +
          (select count(*)::int from public.bookings where client_id = tests.client_id('test_b')),
          0, 'no row of client B is visible in any client table');
select is((select count(*)::int from public.booking_details), 1, 'booking_details shows only own bookings');
select is((select count(*)::int from public.invoice_counters) + (select count(*)::int from public.audit_logs) +
          (select count(*)::int from public.app_events) + (select count(*)::int from public.app_admins),
          0, 'admin-only tables are empty for a client user');
select is((select count(*)::int from public.roles), 2, 'lookups are readable');
select is((select count(*)::int from public.licenses), 1, 'own licence is readable');

-- RPCs with client B's ids fail
select throws_ok(format($$select tests.book(%s, tests.today() + 6, 600, 660)$$, tests.resource_id('test_b', 'B1')),
                 'AB026', null, 'cannot book another client''s resource');
select throws_ok(format('select public.mark_booking_paid(%s)', tests.got_id('b1')), 'AB040', null,
                 'cannot mark another client''s booking paid');
select throws_ok(format($$select public.cancel_booking(%s, 'x', false)$$, tests.got_id('b1')), 'AB040', null,
                 'cannot cancel another client''s booking');
select throws_ok(format('select tests.edit(%s, p_name => %L)', tests.got_id('b1'), 'Hacker'), 'AB040', null,
                 'cannot edit another client''s booking');
select throws_ok(format('select public.update_hourly_rate(%s, 1)', tests.type_id('test_b', 'Cricket')), 'AB040', null,
                 'cannot change another client''s rate');
select throws_ok(format('select public.set_user_status(%s, 0)', tests.user_id('owner_b@test.dev')), 'AB040', null,
                 'cannot disable another client''s user');

-- Bundle: own client, effective rights
select is(public.get_client_bundle('1.0.0') #>> '{client,client_code}', 'test_a', 'bundle is for own client');
select is(jsonb_array_length(public.get_client_bundle('1.0.0') -> 'permissions'), 7, 'owner has all 7 rights');
select is(jsonb_array_length(public.get_client_bundle('1.0.0') -> 'resources'), 3, 'bundle lists the resources');
select tests.login('staff_a@test.dev');
select is(public.get_client_bundle('1.0.0') -> 'permissions',
          '["booking.create", "booking.edit", "booking.mark_paid"]'::jsonb, 'staff get the default staff rights');

-- A session without an active device row (signed in, start_session not done) reads nothing and can't write
select tests.login('owner_a@test.dev', 'phone2');
select is((select count(*)::int from public.clients) + (select count(*)::int from public.booking_details),
          0, 'a session that is not the active phone reads nothing');
select throws_ok('select public.get_client_bundle(null)', 'AB002', null, 'bundle refused for an inactive session');
select throws_ok(format($$select tests.book(%s, tests.today() + 6, 600, 660)$$, tests.resource_id('test_a', 'A1')),
                 'AB002', null, 'writes refused for an inactive session');

-- Replacing the phone
select is(tests.sign_in('owner_a@test.dev', 'test_a', 'phone2') ->> 'status', 'other_device_active',
          'a second phone is told another phone is active');
select is(tests.sign_in('owner_a@test.dev', 'test_a', 'phone2') ->> 'other_device_name', 'Phone phone1',
          'and which phone it is');
select is(tests.sign_in('owner_a@test.dev', 'test_a', 'phone2', true) ->> 'replaced_other', 'true',
          'with replace_other the new phone takes over');
select is((select count(*)::int from public.clients), 1, 'the new phone reads its client');
select tests.login('owner_a@test.dev', 'phone1');
select is((select count(*)::int from public.clients), 0, 'the old phone is cut off at once');
select throws_ok('select public.get_client_bundle(null)', 'AB002', null, 'the old phone gets AB002');
select is((select data_status::int from public.devices where device_uid = 'phone1'), 0,
          'the old phone still sees its own device row turn inactive (Realtime sign-out)');

-- Same phone signing in again just refreshes its session
select tests.login('owner_b@test.dev', 'phone1-new-login');
select is(public.start_session('test_b', 'phone1', '', 'Phone phone1', 'android', '1.0.1', false) ->> 'replaced_other',
          'false', 'the same phone signing in again is accepted');
select is((select count(*)::int from public.devices where data_status = 1), 1, 'still one active phone');

-- Wrong flavor, unregistered email
select tests.login('owner_a@test.dev', 'phone3');
select throws_ok($$select public.start_session('test_b', 'phone3', '', '', 'android', '', false)$$, 'AB004', null,
                 'an account cannot sign in to another business''s app');
select tests.logout();
insert into auth.users (id, email) values (tests.uid('stranger@test.dev'), 'stranger@test.dev');
select tests.login('stranger@test.dev');
select throws_ok($$select public.start_session('test_a', 'p', '', '', 'android', '', false)$$, 'AB001', null,
                 'an email without a users row is refused');

-- Sign out
select tests.login('staff_a@test.dev');
select lives_ok('select public.sign_out_device()', 'sign_out_device runs');
select throws_ok('select public.get_client_bundle(null)', 'AB002', null, 'after sign-out the session is inactive');

select * from finish();
rollback;
