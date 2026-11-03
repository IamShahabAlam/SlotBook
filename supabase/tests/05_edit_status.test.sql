-- Automatic status, Mark Paid, cancel and the edit rules (§8.2, §8.3, §11.3).
begin;
\ir _setup.psql
select plan(26);

select tests.login('owner_a@test.dev');

-- status from the money and cancel fields
select tests.keep('p', tests.book(tests.resource_id('test_a', 'A1'), tests.today() + 5, 600, 660, p_advance => 1000));
select is(tests.got('p') ->> 'booking_status_code', 'pending', 'partly paid → pending');
select is(tests.got('p') ->> 'balance_due', '2000', 'balance due = payable - advance');
select is(public.mark_booking_paid(tests.got_id('p')) ->> 'booking_status_code', 'paid', 'Mark Paid → paid');
select results_eq(format('select balance_due, amount_collected, balance_settled_at is not null from public.booking_details where booking_id = %s',
                         tests.got_id('p')),
                  $$values (0, 3000, true)$$, 'paid: nothing due, full payable collected');
select is(public.mark_booking_paid(tests.got_id('p')) ->> 'booking_status_code', 'paid', 'Mark Paid twice is harmless');
select is(tests.book(tests.resource_id('test_a', 'A1'), tests.today() + 6, 600, 660, p_advance => 3000) ->> 'booking_status_code',
          'paid', 'advance covering the payable → paid');

-- an edit clears Mark Paid and re-evaluates
select is(tests.edit(tests.got_id('p'), p_received => 1500) ->> 'booking_status_code', 'pending',
          'editing a paid booking with less received → pending again');
select is(tests.edit(tests.got_id('p'), p_received => 3000) ->> 'booking_status_code', 'paid',
          'editing with the full amount received → paid');

-- cancel
select tests.keep('c', tests.book(tests.resource_id('test_a', 'A1'), tests.today() + 7, 600, 660, p_advance => 1000));
select throws_ok(format($$select public.cancel_booking(%s, '  ', false)$$, tests.got_id('c')), 'AB027', null,
                 'cancelling needs a reason');
select is(public.cancel_booking(tests.got_id('c'), 'Rain', false) ->> 'booking_status_code', 'cancelled',
          'cancelled with the advance kept');
select is((tests.booking(tests.got_id('c'))).cancel_reason, 'Rain', 'the reason is stored');
select is(public.cancel_booking(tests.got_id('c'), 'Again', true) ->> 'cancel_reason', 'Rain',
          'cancelling twice changes nothing');
select is(public.cancel_booking((tests.book(tests.resource_id('test_a', 'A1'), tests.today() + 8, 600, 660, p_advance => 1000)
                                 ->> 'booking_id')::int, 'Rain', true) ->> 'amount_collected',
          '0', 'advance returned → refunded, nothing collected');
select is(public.cancel_booking((tests.book(tests.resource_id('test_a', 'A1'), tests.today() + 9, 600, 660)
                                 ->> 'booking_id')::int, 'Rain', true) ->> 'booking_status_code',
          'cancelled', 'no advance to return → cancelled, not refunded');
select throws_ok(format('select tests.edit(%s, p_name => %L)', tests.got_id('c'), 'New'), 'AB024', null,
                 'a cancelled booking cannot be edited');
select throws_ok(format('select public.mark_booking_paid(%s)', tests.got_id('c')), 'AB024', null,
                 'a cancelled booking cannot be marked paid');

-- stale edits
select tests.keep('e', tests.book(tests.resource_id('test_a', 'A2'), tests.today() + 5, 600, 660));
select throws_ok(format($$select tests.edit(%s, p_name => 'X', p_use_expected => true,
                                              p_expected => (tests.booking(%1$s)).updated_at - interval '1 second')$$,
                        tests.got_id('e')),
                 'AB025', null, 'an edit based on an older version is refused');
select throws_ok(format($$select tests.edit(%s, p_name => 'X', p_use_expected => true, p_expected => null)$$, tests.got_id('e')),
                 'AB025', null, 'an edit without the expected version is refused');

-- rates: frozen per booking
select lives_ok(format('select public.update_hourly_rate(%s, 5000)', tests.type_id('test_a', 'Cricket')), 'rate changed');
select is((tests.booking(tests.got_id('e'))).total_fee, 3000, 'a rate change never re-prices existing bookings');
select is(tests.edit(tests.got_id('e'), p_end => 720) ->> 'total_fee', '6000',
          'an edit on the same type keeps the agreed rate (2 h x 3000)');
select is(tests.edit(tests.got_id('e'), p_resource_id => tests.resource_id('test_a', 'P1')) ->> 'total_fee', '8000',
          'moving to another type takes that type''s rate (2 h x 4000)');

-- past and already-started bookings
select tests.logout();
update public.bookings set booking_date = tests.today() - 3 where booking_id = tests.got_id('p');
update public.bookings set booking_date = tests.today(), start_minute = 0, end_minute = 60, total_fee = 4000
 where booking_id = tests.got_id('e');
select tests.login('owner_a@test.dev');
select throws_ok(format('select tests.edit(%s, p_name => %L)', tests.got_id('p'), 'New'), 'AB024', null,
                 'a past booking cannot be edited');
select is(tests.edit(tests.got_id('e'), p_name => 'Renamed') ->> 'customer_name', 'Renamed',
          'a started booking can be edited if it keeps its time');
select throws_ok(format('select tests.edit(%s, p_start => 30, p_end => 90)', tests.got_id('e')), 'AB022', null,
                 'but cannot move to a time that has started');

-- guard trigger (defence in depth, even for the SQL editor)
select tests.logout();
select throws_ok(format('update public.bookings set invoice_number = 999 where booking_id = %s', tests.got_id('e')),
                 'AB024', 'Booking identity fields cannot change.', 'identity fields are frozen');

select * from finish();
rollback;
