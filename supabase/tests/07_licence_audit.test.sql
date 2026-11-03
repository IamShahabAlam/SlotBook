-- Licence switch with the Gist JSON shape (§15) and the compact audit trail (§8.4).
begin;
\ir _setup.psql
select plan(16);

-- get_app_access
select tests.as_anon();
select is((select array_agg(k order by k) from jsonb_object_keys(public.get_app_access('test_a') -> 'entry') k),
          array['AppDisableAfterDate', 'DataEntryDate', 'DataEntryStatus', 'IsAppEnable', 'LastUpdateDate', 'UserName'],
          'the entry has exactly the Gist keys');
select is(public.get_app_access('test_a') -> 'entry',
          jsonb_build_object('IsAppEnable', true, 'AppDisableAfterDate', '', 'DataEntryStatus', 1,
                             'DataEntryDate', tests.today()::text, 'LastUpdateDate', tests.today()::text, 'UserName', ''),
          'a paid licence: enabled, no end date');
select is(public.get_app_access('nobody') - 'server_time', '{"found": false, "entry": null}'::jsonb,
          'an unknown client is not found (the app fails closed)');
select ok(public.get_app_access('nobody') ? 'server_time', 'server_time is always returned');
select tests.logout();

insert into auth.users (id, email) values (tests.uid('admin@devcat.dev'), 'admin@devcat.dev');
insert into public.app_admins (auth_user_id, full_name, email) values (tests.uid('admin@devcat.dev'), 'Shahab', 'admin@devcat.dev');

-- trial ended yesterday → writes blocked
update public.licenses set is_app_enable = false, app_disable_after_date = tests.today() - 1,
       updated_by_app_admin_id = (select app_admin_id from public.app_admins)
 where client_id = tests.client_id('test_a');
select is(public.get_app_access('test_a') #>> '{entry,UserName}', 'Shahab', 'UserName is the admin who last edited it');
select tests.login('owner_a@test.dev');
select throws_ok(format($$select tests.book(%s, tests.today() + 5, 600, 660)$$, tests.resource_id('test_a', 'A1')),
                 'AB003', null, 'an expired trial blocks bookings');
select throws_ok(format('select public.update_hourly_rate(%s, 100)', tests.type_id('test_a', 'Cricket')), 'AB003', null,
                 'and settings writes');
select tests.logout();

update public.licenses set app_disable_after_date = tests.today() where client_id = tests.client_id('test_a');
select tests.login('owner_a@test.dev');
select lives_ok(format($$select tests.keep('b', tests.book(%s, tests.today() + 5, 600, 660))$$, tests.resource_id('test_a', 'A1')),
                'the trial still works on its last day');
select tests.logout();

update public.licenses set app_disable_after_date = null where client_id = tests.client_id('test_a');
select tests.login('owner_a@test.dev');
select throws_ok(format('select public.mark_booking_paid(%s)', tests.got_id('b')), 'AB003', null,
                 'disabled without a date blocks at once');
select tests.logout();

update public.licenses set data_status = 0 where client_id = tests.client_id('test_a');
select tests.login('owner_a@test.dev');
select lives_ok(format('select public.mark_booking_paid(%s)', tests.got_id('b')),
                'an ignored licence entry (data_status 0) lets the app run');
select tests.logout();

delete from public.licenses where client_id = tests.client_id('test_b');
select tests.login('owner_b@test.dev');
select throws_ok(format($$select tests.book(%s, tests.today() + 5, 600, 660)$$, tests.resource_id('test_b', 'B1')),
                 'AB003', null, 'no licence row blocks writes (fail closed)');

-- audit: '{}' on insert, only changed fields on update, nothing for no-op or excluded fields
select tests.logout();
select is((select changed_fields from public.audit_logs where table_name = 'bookings' and record_id = tests.got_id('b')
            and action = 'insert'),
          '{}'::jsonb, 'an insert is logged with no diff');
select is((select array_agg(k order by k) from public.audit_logs a, jsonb_object_keys(a.changed_fields) k
            where a.table_name = 'bookings' and a.record_id = tests.got_id('b') and a.action = 'update'),
          array['balance_settled_at', 'booking_status_id'], 'Mark Paid logs only the fields it changed');
select is((select user_id from public.audit_logs where table_name = 'bookings' and record_id = tests.got_id('b')
            and action = 'update'),
          tests.user_id('owner_a@test.dev'), 'the audit row names the user');
select tests.keep('audits', to_jsonb((select count(*) from public.audit_logs)));
update public.bookings set notes = notes where booking_id = tests.got_id('b');
select tests.login('owner_a@test.dev');
select public.get_client_bundle('9.9.9');   -- touches last_seen_at and app_version only
select tests.logout();
select is((select count(*)::int from public.audit_logs), (tests.got('audits'))::int,
          'no audit row when nothing meaningful changed');
select is((select array_agg(k order by k)
             from (select changed_fields from public.audit_logs
                    where table_name = 'licenses' and action = 'update' order by audit_log_id limit 1) a,
                  jsonb_object_keys(a.changed_fields) k),
          array['app_disable_after_date', 'is_app_enable', 'updated_by_app_admin_id'], 'licence edits are audited too');

select * from finish();
rollback;
