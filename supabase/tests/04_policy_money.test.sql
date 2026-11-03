-- Booking time policy, sessions, money and customer validation (§11.2, §11.3).
begin;
\ir _setup.psql
select plan(34);

-- extra clients: a night venue (4 PM - 2 AM), a space rental without discounts, an event venue (sessions, manual price)
select public.admin_create_client($j${
  "client_code": "test_night", "name": "Night Arena", "business_profile_code": "sports_venue", "plan_code": "monthly",
  "open_start_minute": 960, "open_end_minute": 1560,
  "resource_types": [{"name": "Padel", "icon_key": "sports_tennis", "tone": "blue", "hourly_rate": 4000,
                      "resources": [{"name": "N1"}]}]}$j$);
select public.admin_create_client($j${
  "client_code": "test_space", "name": "Space", "business_profile_code": "space_rental", "plan_code": "monthly",
  "allow_discount": false,
  "resource_types": [{"name": "Room", "icon_key": "meeting_room", "tone": "emerald", "hourly_rate": 1000,
                      "resources": [{"name": "S1"}]},
                     {"name": "Unpriced", "icon_key": "meeting_room", "tone": "blue", "hourly_rate": null,
                      "resources": [{"name": "S2"}]}]}$j$);
select public.admin_create_client($j${
  "client_code": "test_event", "name": "Hall", "business_profile_code": "event_venue", "plan_code": "monthly",
  "resource_types": [{"name": "Banquet", "icon_key": "event", "tone": "emerald", "resources": [{"name": "E1"}]}]}$j$);
select tests.add_user('test_night', 'owner_n@test.dev', 'owner');
select tests.add_user('test_space', 'owner_s@test.dev', 'owner');
select tests.add_user('test_event', 'owner_e@test.dev', 'owner');
select tests.sign_in('owner_n@test.dev', 'test_night');
select tests.sign_in('owner_s@test.dev', 'test_space');
select tests.sign_in('owner_e@test.dev', 'test_event');

-- sports venue: 30-minute steps, 30 min to 24 h
select tests.login('owner_a@test.dev');
select throws_ok(format($$select tests.book(%s, tests.today() + 3, 615, 675)$$, tests.resource_id('test_a', 'A1')),
                 'AB021', 'Times must be in 30-minute steps.', 'start must be on a step');
select throws_ok(format($$select tests.book(%s, tests.today() + 3, 600, 645)$$, tests.resource_id('test_a', 'A1')),
                 'AB021', 'Times must be in 30-minute steps.', 'duration must be whole steps');
select throws_ok(format($$select tests.book(%s, tests.today() + 3, 600, 600)$$, tests.resource_id('test_a', 'A1')),
                 'AB021', 'Invalid booking time.', 'end must be after start');
select throws_ok(format($$select tests.book(%s, tests.today() + 3, 1440, 1500)$$, tests.resource_id('test_a', 'A1')),
                 'AB021', 'Invalid booking time.', 'start must be before 24:00');
select throws_ok(format($$select tests.book(%s, tests.today() + 3, 0, 1470)$$, tests.resource_id('test_a', 'A1')),
                 'AB021', 'Duration must be between 30 and 1440 minutes.', 'at most 24 hours');
select lives_ok(format($$select tests.book(%s, tests.today() + 3, 120, 1560)$$, tests.resource_id('test_a', 'A2')),
                'exactly 24 hours, crossing midnight, is allowed');
select throws_ok(format($$select tests.book(%s, tests.today() + 731, 600, 660)$$, tests.resource_id('test_a', 'A1')),
                 'AB021', 'Bookings can be made up to 2 years ahead.', 'not more than 2 years ahead');
select lives_ok(format($$select tests.book(%s, tests.today() + 730, 600, 660)$$, tests.resource_id('test_a', 'A1')),
                'exactly 2 years ahead is allowed');
select throws_ok(format($$select tests.book(%s, tests.today(), 0, 30)$$, tests.resource_id('test_a', 'A1')),
                 'AB022', null, 'a slot that has started cannot be booked');
select throws_ok(format($$select tests.book(%s, tests.today() + 3, 600, 660, p_session_id => %s)$$,
                        tests.resource_id('test_a', 'A1'), tests.session_id('test_event', 'Lunch')),
                 'AB021', 'This business does not use sessions.', 'a session id is refused where sessions are not used');

-- opening hours 960-1560 (4 PM - 2 AM), including the early-morning tail of the previous night
select tests.login('owner_n@test.dev');
select lives_ok(format($$select tests.book(%s, tests.today() + 3, 960, 1020)$$, tests.resource_id('test_night', 'N1')),
                'inside opening hours');
select throws_ok(format($$select tests.book(%s, tests.today() + 3, 900, 990)$$, tests.resource_id('test_night', 'N1')),
                 'AB021', 'This time is outside opening hours.', 'before opening');
select lives_ok(format($$select tests.book(%s, tests.today() + 3, 1380, 1560)$$, tests.resource_id('test_night', 'N1')),
                '11 PM past midnight until closing');
select throws_ok(format($$select tests.book(%s, tests.today() + 4, 1380, 1620)$$, tests.resource_id('test_night', 'N1')),
                 'AB021', 'This time is outside opening hours.', 'past closing');
select lives_ok(format($$select tests.book(%s, tests.today() + 5, 0, 120)$$, tests.resource_id('test_night', 'N1')),
                'the early-morning tail on its own date');
select throws_ok(format($$select tests.book(%s, tests.today() + 5, 60, 180)$$, tests.resource_id('test_night', 'N1')),
                 'AB021', 'This time is outside opening hours.', 'running past the tail''s closing');

-- full day (space rental): 24 hours from any step
select tests.login('owner_s@test.dev');
select lives_ok(format($$select tests.book(%s, tests.today() + 3, 600, 2040)$$, tests.resource_id('test_space', 'S1')),
                'full day from 10 AM to 10 AM next day');
select throws_ok(format($$select tests.book(%s, tests.today() + 5, 600, 630)$$, tests.resource_id('test_space', 'S1')),
                 'AB021', 'Times must be in 60-minute steps.', 'space rental uses 60-minute steps');

-- sessions (event venue): only whole sessions, priced by hand
select tests.login('owner_e@test.dev');
select is(tests.book(tests.resource_id('test_event', 'E1'), tests.today() + 3, 1140, 1440, p_manual_fee => 150000,
                     p_session_id => tests.session_id('test_event', 'Dinner')) ->> 'total_fee',
          '150000', 'a whole session at the typed price');
select throws_ok(format($$select tests.book(%s, tests.today() + 4, 1140, 1440, p_manual_fee => 1000)$$,
                        tests.resource_id('test_event', 'E1')),
                 'AB021', 'Please choose one of the available sessions.', 'a free time range is refused');
select throws_ok(format($$select tests.book(%s, tests.today() + 4, 1140, 1380, p_manual_fee => 1000, p_session_id => %s)$$,
                        tests.resource_id('test_event', 'E1'), tests.session_id('test_event', 'Dinner')),
                 'AB021', 'Please choose one of the available sessions.', 'session minutes must match exactly');
select throws_ok(format($$select tests.book(%s, tests.today() + 5, 720, 1080, p_session_id => %s)$$,
                        tests.resource_id('test_event', 'E1'), tests.session_id('test_event', 'Lunch')),
                 'AB023', 'The price must be more than zero.', 'manual pricing needs a price');

-- money
select tests.login('owner_a@test.dev');
select is(tests.book(tests.resource_id('test_a', 'A1'), tests.today() + 10, 600, 690, p_manual_fee => 1) ->> 'total_fee',
          '4500', 'hourly fee = 90 min x 3000/h; a sent fee is ignored');
select results_eq(format($$select (b ->> 'discount')::int, (b ->> 'advance_paid')::int, (b ->> 'balance_due')::int
                             from tests.book(%s, tests.today() + 11, 600, 660, p_advance => 999999, p_discount => 500) b$$,
                         tests.resource_id('test_a', 'A1')),
                  $$values (500, 2500, 0)$$, 'advance is clamped to the payable amount');
select is(tests.book(tests.resource_id('test_a', 'A1'), tests.today() + 12, 600, 660, p_advance => -50) ->> 'advance_paid',
          '0', 'a negative advance becomes 0');
select throws_ok(format($$select tests.book(%s, tests.today() + 13, 600, 660, p_discount => 3001)$$,
                        tests.resource_id('test_a', 'A1')),
                 'AB023', 'Discount must be between 0 and the fee.', 'discount above the fee');
select throws_ok(format($$select tests.book(%s, tests.today() + 13, 600, 660, p_discount => -1)$$,
                        tests.resource_id('test_a', 'A1')),
                 'AB023', 'Discount must be between 0 and the fee.', 'negative discount');
select tests.login('owner_s@test.dev');
select throws_ok(format($$select tests.book(%s, tests.today() + 13, 600, 660, p_discount => 100)$$,
                        tests.resource_id('test_space', 'S1')),
                 'AB023', 'Discounts are not enabled for this business.', 'discount where the feature is off');
select throws_ok(format($$select tests.book(%s, tests.today() + 13, 600, 660)$$, tests.resource_id('test_space', 'S2')),
                 'AB023', 'No hourly rate is set for this resource type.', 'hourly pricing needs a rate');

-- customer details
select tests.login('owner_a@test.dev');
select throws_ok(format($$select tests.book(%s, tests.today() + 14, 600, 660, p_name => '  ')$$,
                        tests.resource_id('test_a', 'A1')),
                 'AB028', 'Customer name is required.', 'name is required');
select throws_ok(format($$select tests.book(%s, tests.today() + 14, 600, 660, p_phone => '030012345')$$,
                        tests.resource_id('test_a', 'A1')),
                 'AB028', 'Phone number must have 10 or 11 digits.', 'phone needs 10 or 11 digits');
select is(tests.book(tests.resource_id('test_a', 'A1'), tests.today() + 14, 600, 660, p_phone => '0300 123-4567',
                     p_email => ' Ali@Example.COM ') ->> 'customer_phone',
          '03001234567', 'phone is stored as digits only');
select throws_ok(format($$select tests.book(%s, tests.today() + 15, 600, 660, p_email => 'not-an-email')$$,
                        tests.resource_id('test_a', 'A1')),
                 'AB028', 'Email address is not valid.', 'email must be valid');
select throws_ok(format($$select tests.book(%s, tests.today() + 15, 600, 660, p_notes => repeat('x', 121))$$,
                        tests.resource_id('test_a', 'A1')),
                 'AB028', 'Notes can be at most 120 characters.', 'notes at most 120 characters');

select * from finish();
rollback;
