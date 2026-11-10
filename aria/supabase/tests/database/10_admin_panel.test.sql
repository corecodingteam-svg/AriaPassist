begin;
create extension if not exists pgtap with schema extensions;
-- Independent of real admins in this database (rolled back at the end).
delete from public.admins;
select plan(16);

insert into auth.users (id, email, aud, role, raw_user_meta_data) values
  ('a1000000-0000-0000-0000-0000000000a1', 'boss@t.dev', 'authenticated', 'authenticated', '{"name":"Boss"}'),
  ('f1000000-0000-0000-0000-0000000000f1', 'money@t.dev', 'authenticated', 'authenticated', '{"name":"Money"}'),
  ('c1000000-0000-0000-0000-0000000000c1', 'cust@t.dev', 'authenticated', 'authenticated', '{"name":"Customer Kumar"}');
insert into public.reminders (circle_id, created_by, title)
select id, owner_id, 'Secret medical thing' from public.circles where owner_id = 'c1000000-0000-0000-0000-0000000000c1';

select set_config('aria.actor', 'ops@test', true);
select public.admin_set_role('a1000000-0000-0000-0000-0000000000a1', 'super', 'bootstrap for test');
select public.admin_set_role('f1000000-0000-0000-0000-0000000000f1', 'finance', 'finance for test');

create function pg_temp.login(uid text, aal text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', aal)::text, true);
$$;
grant execute on function pg_temp.login(text, text) to authenticated;

set local role authenticated;

-- Without the second factor: identity yes, admin data no.
select pg_temp.login('a1000000-0000-0000-0000-0000000000a1', 'aal1');
select is((select public.admin_me() ->> 'role'), 'super', 'admin_me works before MFA (panel asks for it)');
select is((select public.admin_me() ->> 'aal'), 'aal1', 'and reports the assurance level');
select throws_like($$select public.admin_overview()$$, '%two-factor%', 'reads need two-factor sign-in');
select throws_like($$select public.admin_suspend_user('c1000000-0000-0000-0000-0000000000c1', 'no mfa yet')$$,
  '%two-factor%', 'actions need two-factor sign-in');

-- Regular users get nothing.
select pg_temp.login('c1000000-0000-0000-0000-0000000000c1', 'aal2');
select is((select public.admin_me() ->> 'role'), null, 'non-admins have no role');
select throws_ok($$select public.admin_overview()$$, '42501', null, 'non-admins cannot read the overview');
select throws_ok($$select public.admin_search_users('', 10)$$, '42501', null, 'non-admins cannot search users');

-- Finance (aal2): reads yes, actions no, admin list no.
select pg_temp.login('f1000000-0000-0000-0000-0000000000f1', 'aal2');
select ok((select (public.admin_overview() ->> 'users')::int >= 3), 'finance reads the overview');
select ok(jsonb_array_length(public.admin_report('revenue_monthly', 50, 0)) >= 0, 'finance reads reports');
select throws_like($$select public.admin_report('users; drop table x', 10, 0)$$, '%unknown report%',
  'report names are whitelisted');
select throws_ok($$select public.admin_list_admins()$$, '42501', null, 'only super lists admins');

-- Super (aal2): search + detail, metadata only, viewing is logged.
select pg_temp.login('a1000000-0000-0000-0000-0000000000a1', 'aal2');
select is((select public.admin_search_users('Kumar', 10) -> 0 ->> 'email'), 'cust@t.dev', 'search by name');
select is((select public.admin_search_users('cust@', 10) -> 0 ->> 'name'), 'Customer Kumar', 'search by email');
select ok(position('Secret medical thing' in public.admin_user_detail('c1000000-0000-0000-0000-0000000000c1')::text) = 0,
  'user detail never contains reminder text');
select is(jsonb_array_length(public.admin_list_admins()), 2, 'super lists admins');
reset role;
select is((select count(*)::int from public.admin_actions
            where action = 'user.viewed' and target_user = 'c1000000-0000-0000-0000-0000000000c1'), 1,
  'opening a user is logged');

select * from finish();
rollback;
