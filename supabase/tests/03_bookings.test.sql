-- No double booking, idempotent retries and gapless per-client invoice numbers (§6.5, §11.3, §12).
begin;
\ir _setup.psql
select plan(19);

select tests.login('owner_a@test.dev');

-- overlap rules on resource A1
select is(tests.keep('first', tests.book(tests.resource_id('test_a', 'A1'), tests.today() + 5, 600, 660)) ->> 'invoice_no',
          'INV-' || tests.client_id('test_a') || '-00001', 'first booking gets INV-<client>-00001');
select throws_ok(format($$select tests.book(%s, tests.today() + 5, 630, 690)$$, tests.resource_id('test_a', 'A1')),
                 'AB020', null, 'an overlapping booking on the same resource is refused');
select throws_ok(format($$select tests.book(%s, tests.today() + 5, 540, 720)$$, tests.resource_id('test_a', 'A1')),
                 'AB020', null, 'a booking that covers another is refused');
select is(tests.book(tests.resource_id('test_a', 'A1'), tests.today() + 5, 660, 720) ->> 'invoice_no',
          'INV-' || tests.client_id('test_a') || '-00002', 'touching ranges do not clash, and no invoice gap after the refusals');
select lives_ok(format($$select tests.book(%s, tests.today() + 5, 600, 660)$$, tests.resource_id('test_a', 'A2')),
                'another resource at the same time is fine');
select lives_ok(format($$select public.cancel_booking(%s, 'Rain', false)$$, tests.got_id('first')), 'cancel');
select lives_ok(format($$select tests.book(%s, tests.today() + 5, 600, 660)$$, tests.resource_id('test_a', 'A1')),
                'a cancelled booking frees its time');

-- crossing midnight: 23:00-01:00 blocks 00:00-01:00 of the next date
select lives_ok(format($$select tests.book(%s, tests.today() + 8, 1380, 1500)$$, tests.resource_id('test_a', 'A1')),
                'a booking may cross midnight');
select throws_ok(format($$select tests.book(%s, tests.today() + 9, 0, 60)$$, tests.resource_id('test_a', 'A1')),
                 'AB020', null, 'the next date''s early hours are taken by the cross-midnight booking');
select lives_ok(format($$select tests.book(%s, tests.today() + 9, 60, 120)$$, tests.resource_id('test_a', 'A1')),
                'right after the cross-midnight booking is free');
select throws_ok(format($$select tests.book(%s, tests.today() + 8, 1320, 1440)$$, tests.resource_id('test_a', 'A1')),
                 'AB020', null, 'a booking on the start date overlapping the cross-midnight one is refused');

-- idempotency: the same request_uid twice returns the first booking and numbers it once
select tests.keep('retry1', tests.book(tests.resource_id('test_a', 'P1'), tests.today() + 5, 600, 660,
                                       p_uid => 'aaaaaaaa-0000-4000-8000-000000000001'));
select tests.keep('counter', to_jsonb(tests.counter('test_a')));
select is(tests.book(tests.resource_id('test_a', 'P1'), tests.today() + 5, 600, 660,
                     p_uid => 'aaaaaaaa-0000-4000-8000-000000000001') ->> 'booking_id',
          tests.got('retry1') ->> 'booking_id', 'a retry returns the same booking');
select is(tests.counter('test_a'), (tests.got('counter'))::int, 'the invoice counter advanced once');
select is((select count(*)::int from public.bookings where request_uid = 'aaaaaaaa-0000-4000-8000-000000000001'),
          1, 'only one row for the request');

-- numbers: gapless, per client
select is((select array_agg(invoice_number order by invoice_number) from public.bookings),
          (select array_agg(n) from generate_series(1, (select count(*)::int from public.bookings)) n),
          'client A invoice numbers are 1..n with no gaps');
select tests.login('owner_b@test.dev');
select throws_ok(format($$select tests.book(%s, tests.today() + 5, 900, 960, p_uid => 'aaaaaaaa-0000-4000-8000-000000000001')$$,
                        tests.resource_id('test_b', 'B1')),
                 '23505', null, 'another client''s request_uid is refused, never answered with that client''s booking');
select is(tests.book(tests.resource_id('test_b', 'B1'), tests.today() + 5, 600, 660) ->> 'invoice_no',
          'INV-' || tests.client_id('test_b') || '-00001', 'each client numbers from 1');

-- numbers past 99999 are not truncated
select tests.logout();
update public.invoice_counters set last_invoice_number = 99998 where client_id = tests.client_id('test_b');
select tests.login('owner_b@test.dev');
select is(tests.book(tests.resource_id('test_b', 'B1'), tests.today() + 6, 600, 660) ->> 'invoice_no',
          'INV-' || tests.client_id('test_b') || '-99999', '5 digits up to 99999');
select is(tests.book(tests.resource_id('test_b', 'B1'), tests.today() + 7, 600, 660) ->> 'invoice_no',
          'INV-' || tests.client_id('test_b') || '-100000', '100000 keeps all its digits');

select * from finish();
rollback;
