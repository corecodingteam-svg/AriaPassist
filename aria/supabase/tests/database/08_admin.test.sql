begin;
create extension if not exists pgtap with schema extensions;
-- Independent of real admins in this database (rolled back at the end).
delete from public.admins;
select plan(31);

insert into auth.users (id, email, aud, role, raw_user_meta_data) values
  ('a0000000-0000-0000-0000-0000000000a8', 'super@t.dev', 'authenticated', 'authenticated', '{"name":"Super"}'),
  ('b0000000-0000-0000-0000-0000000000b8', 'support@t.dev', 'authenticated', 'authenticated', '{"name":"Sup"}'),
  ('c0000000-0000-0000-0000-0000000000c8', 'user@t.dev', 'authenticated', 'authenticated', '{"name":"User"}'),
  ('d0000000-0000-0000-0000-0000000000d8', 'fin@t.dev', 'authenticated', 'authenticated', '{"name":"Fin"}');

-- Admins have completed two-factor sign-in (aal2); see 10_admin_panel for aal1.
create function pg_temp.login(uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.login(text) to authenticated;

create temp table pc as select id from public.circles where owner_id = 'c0000000-0000-0000-0000-0000000000c8';
grant select on pc to authenticated;

-- Bootstrap from the console (break-glass), named.
select set_config('aria.actor', 'ops@aria.test', true);
select lives_ok($$select public.admin_set_role('a0000000-0000-0000-0000-0000000000a8', 'super', 'bootstrap first admin')$$,
  'console can bootstrap the first super-admin');
select is((select actor from public.admin_actions order by at desc limit 1), 'console:ops@aria.test',
  'console actions are attributed');

set local role authenticated;
select pg_temp.login('a0000000-0000-0000-0000-0000000000a8');
select lives_ok($$select public.admin_set_role('b0000000-0000-0000-0000-0000000000b8', 'support', 'new support hire')$$,
  'super grants support');
select lives_ok($$select public.admin_set_role('d0000000-0000-0000-0000-0000000000d8', 'finance', 'finance team')$$,
  'super grants finance');
select throws_like($$select public.admin_set_role('a0000000-0000-0000-0000-0000000000a8', null, 'leaving')$$,
  '%last super-admin%', 'cannot remove the last super-admin');
select throws_like($$select public.admin_suspend_user('c0000000-0000-0000-0000-0000000000c8', 'x')$$,
  '%reason is required%', 'a real reason is required');

-- Regular users and finance can't act.
select pg_temp.login('c0000000-0000-0000-0000-0000000000c8');
select throws_ok($$select public.admin_suspend_user('b0000000-0000-0000-0000-0000000000b8', 'nope nope')$$,
  '42501', null, 'regular users cannot call admin functions');
select is((select count(*)::int from public.admins), 0, 'regular users see no admin rows');
select pg_temp.login('d0000000-0000-0000-0000-0000000000d8');
select throws_ok($$select public.admin_suspend_user('c0000000-0000-0000-0000-0000000000c8', 'finance tries')$$,
  '42501', null, 'finance is read-only');
select is((select role from public.admins), 'finance', 'an admin sees only their own role');

-- Support suspends a user.
select pg_temp.login('b0000000-0000-0000-0000-0000000000b8');
select throws_like($$select public.admin_suspend_user('b0000000-0000-0000-0000-0000000000b8', 'testing self')$$,
  '%yourself%', 'cannot suspend yourself');
select throws_ok($$select public.admin_suspend_user('a0000000-0000-0000-0000-0000000000a8', 'support vs super')$$,
  '42501', null, 'support cannot suspend an admin');
select lives_ok($$select public.admin_suspend_user('c0000000-0000-0000-0000-0000000000c8', 'spam invites reported')$$,
  'support suspends a user');
reset role;
select ok((select banned_until > now() + interval '100 years' from auth.users
            where id = 'c0000000-0000-0000-0000-0000000000c8'), 'sign-in is banned');
select is((select suspended_reason from public.users where id = 'c0000000-0000-0000-0000-0000000000c8'),
  'spam invites reported', 'reason recorded');

-- The suspended user is locked out of the API and the tables.
set local role authenticated;
select pg_temp.login('c0000000-0000-0000-0000-0000000000c8');
select throws_like($$select public.check_request()$$, '%account suspended%', 'API pre-request refuses them (403)');
select is((select count(*)::int from public.circles), 0, 'RLS hides all rows from a suspended user');
update public.users set suspended_at = null where id = 'c0000000-0000-0000-0000-0000000000c8';
reset role;
select isnt((select suspended_at from public.users where id = 'c0000000-0000-0000-0000-0000000000c8'), null,
  'cannot lift their own suspension');
set local role authenticated;
select pg_temp.login('a0000000-0000-0000-0000-0000000000a8');
select lives_ok($$select public.check_request()$$, 'others are unaffected');
select lives_ok($$select public.admin_unsuspend_user('c0000000-0000-0000-0000-0000000000c8', 'appeal accepted')$$,
  'unsuspend');
select pg_temp.login('c0000000-0000-0000-0000-0000000000c8');
select ok((select count(*) from public.circles) > 0, 'access restored');
reset role;
select is((select banned_until from auth.users where id = 'c0000000-0000-0000-0000-0000000000c8'), null, 'ban lifted');

-- Grant plan: extends, never auto-renews, logged.
set local role authenticated;
select pg_temp.login('b0000000-0000-0000-0000-0000000000b8');
select ok(public.admin_grant_plan((select id from pc),
  'personal', 30, 'goodwill after outage') > now() + interval '29 days', 'grant 30 days of Personal');
select ok(public.admin_grant_plan((select id from pc),
  'personal', 30, 'second month goodwill') > now() + interval '59 days', 'a second grant extends from the first');
select throws_like($$select public.admin_grant_plan((select id from pc), 'family', 30, 'wrong circle')$$,
  '%does not fit%', 'Family cannot go on a personal circle');

-- Promo codes.
select is(public.admin_create_promo('launch50', 'personal', 30, 100, null, 'launch', 'launch campaign'), 'LAUNCH50',
  'create promo');
select lives_ok($$select public.admin_disable_promo('LAUNCH50', 'campaign over')$$, 'disable promo');
reset role;

-- The log is append-only, even for the console.
select throws_ok($$update public.admin_actions set reason = 'edited'$$, '42501', null, 'log rows cannot be edited');
select throws_ok($$delete from public.admin_actions$$, '42501', null, 'log rows cannot be deleted');

-- Read-only support login: reports yes, raw tables and writes no.
grant support_readonly to postgres;
grant usage on schema extensions to support_readonly;  -- pgTAP itself (test only)
set local role support_readonly;
select throws_ok($$select count(*) from public.users$$, '42501', null, 'support login cannot read raw tables');
select is((select count(*)::int from reports.admin_activity) >= 9, true, 'support login reads the reports');
reset role;

select * from finish();
rollback;
