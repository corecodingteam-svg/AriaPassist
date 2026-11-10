begin;
create extension if not exists pgtap with schema extensions;
select plan(21);

insert into auth.users (id, email, aud, role, raw_user_meta_data) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a@t.dev', 'authenticated', 'authenticated', '{"name":"Asha"}'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'b@t.dev', 'authenticated', 'authenticated', '{"name":"Bala"}'),
  ('cccccccc-0000-0000-0000-000000000003', 'c@t.dev', 'authenticated', 'authenticated', '{"name":"Chitra"}'),
  ('dddddddd-0000-0000-0000-000000000004', 'd@t.dev', 'authenticated', 'authenticated', '{"name":"Dadi"}');

create function pg_temp.login(uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.login(text) to authenticated;

-- A creates a family circle (as the app does) and it's upgraded by billing.
set local role authenticated;
select pg_temp.login('aaaaaaaa-0000-0000-0000-000000000001');
insert into public.circles (id, name, type, owner_id)
values ('f0000000-0000-0000-0000-00000000000f', 'Sharma family', 'family', 'aaaaaaaa-0000-0000-0000-000000000001');
-- The app inserts with RETURNING (PostgREST .select()), which needs the
-- new row to pass the SELECT policy before the owner trigger's membership.
select lives_ok(
  $$insert into public.circles (name, type, owner_id)
    values ('Returning check', 'team', 'aaaaaaaa-0000-0000-0000-000000000001')
    returning id$$,
  'owner can INSERT … RETURNING a new circle');
reset role;
update public.circles set plan_id = (select id from public.plans where code = 'family')
  where id = 'f0000000-0000-0000-0000-00000000000f';

set local role authenticated;
select pg_temp.login('aaaaaaaa-0000-0000-0000-000000000001');
insert into public.invites (id, circle_id, role, created_by) values
  ('11111111-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-00000000000f', 'member', 'aaaaaaaa-0000-0000-0000-000000000001'),
  ('22222222-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-00000000000f', 'dependent', 'aaaaaaaa-0000-0000-0000-000000000001'),
  ('33333333-0000-0000-0000-000000000003', 'f0000000-0000-0000-0000-00000000000f', 'member', 'aaaaaaaa-0000-0000-0000-000000000001');
reset role;
update public.invites set expires_at = now() - interval '1 minute' where id = '33333333-0000-0000-0000-000000000003';
create temp table tok as select id, token from public.invites;
grant select on tok to authenticated;

-- B previews and accepts.
set local role authenticated;
select pg_temp.login('bbbbbbbb-0000-0000-0000-000000000002');
select is((select circle_name || '/' || inviter_name || '/' || role::text
           from public.preview_invite((select token from tok where id = '11111111-0000-0000-0000-000000000001'))),
  'Sharma family/Asha/member', 'invitee can preview before joining');
select is(public.accept_invite((select token from tok where id = '11111111-0000-0000-0000-000000000001')),
  'f0000000-0000-0000-0000-00000000000f'::uuid, 'accept returns the circle');
select is((select count(*)::int from public.circles where id = 'f0000000-0000-0000-0000-00000000000f'), 1,
  'after joining, B can see the circle');
select is((select count(*)::int from public.users), 2, 'B sees fellow member names');

-- Single use, expiry.
select pg_temp.login('cccccccc-0000-0000-0000-000000000003');
select throws_ok(format('select public.accept_invite(%L)', (select token from tok where id = '11111111-0000-0000-0000-000000000001')),
  'P0001', null, 'invites are single-use');
select throws_ok(format('select public.accept_invite(%L)', (select token from tok where id = '33333333-0000-0000-0000-000000000003')),
  'P0001', null, 'expired invites are rejected');
select throws_ok($$select public.accept_invite('nope')$$, 'P0002', null, 'unknown tokens are rejected');

-- Dadi joins as a dependent.
select pg_temp.login('dddddddd-0000-0000-0000-000000000004');
select lives_ok(format('select public.accept_invite(%L)', (select token from tok where id = '22222222-0000-0000-0000-000000000002')),
  'dependent joins');

-- Assignment rules.
select pg_temp.login('aaaaaaaa-0000-0000-0000-000000000001');
select lives_ok($$
  insert into public.reminders (id, circle_id, created_by, assigned_to, title)
  values ('aaaa0000-0000-0000-0000-00000000000a', 'f0000000-0000-0000-0000-00000000000f',
          'aaaaaaaa-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000004', 'BP tablet')
$$, 'owner assigns a reminder to the dependent');
select is((select count(*)::int from public.audit_logs where action = 'reminder.assigned'), 1,
  'assignment is audited');

select pg_temp.login('bbbbbbbb-0000-0000-0000-000000000002');
select throws_ok($$
  insert into public.reminders (circle_id, created_by, assigned_to, title)
  values ('f0000000-0000-0000-0000-00000000000f', 'bbbbbbbb-0000-0000-0000-000000000002',
          'dddddddd-0000-0000-0000-000000000004', 'x')
$$, '42501', null, 'members cannot assign by default');

select pg_temp.login('aaaaaaaa-0000-0000-0000-000000000001');
update public.circles set settings_json = '{"members_can_assign": true}'
  where id = 'f0000000-0000-0000-0000-00000000000f';
select pg_temp.login('bbbbbbbb-0000-0000-0000-000000000002');
select lives_ok($$
  insert into public.reminders (circle_id, created_by, assigned_to, title)
  values ('f0000000-0000-0000-0000-00000000000f', 'bbbbbbbb-0000-0000-0000-000000000002',
          'dddddddd-0000-0000-0000-000000000004', 'Walk')
$$, '…unless the circle allows it');

-- The dependent sees what was assigned; the creator sees its status.
select pg_temp.login('dddddddd-0000-0000-0000-000000000004');
select is((select count(*)::int from public.reminders where assigned_to = 'dddddddd-0000-0000-0000-000000000004'), 2,
  'dependent sees reminders assigned to them');
select lives_ok($$update public.reminders set status = 'done', last_done_at = now()
  where id = 'aaaa0000-0000-0000-0000-00000000000a'$$, 'dependent marks it done');
with u as (update public.memberships set settings_json = '{}'
           where user_id = 'dddddddd-0000-0000-0000-000000000004' returning 1)
select is(count(*)::int, 0, 'dependents cannot change their own membership (Simple Mode lock)') from u;
select pg_temp.login('aaaaaaaa-0000-0000-0000-000000000001');
select is((select status::text from public.reminders where id = 'aaaa0000-0000-0000-0000-00000000000a'), 'done',
  'owner sees the dependent completed it');
select lives_ok($$update public.memberships set settings_json = '{"simple_lock": {"pin_hash": "x"}}'
  where user_id = 'dddddddd-0000-0000-0000-000000000004' and circle_id = 'f0000000-0000-0000-0000-00000000000f'$$,
  'admin can lock Simple Mode for a dependent');

-- Leaving / ownership.
select throws_ok($$select public.leave_circle('f0000000-0000-0000-0000-00000000000f')$$, 'P0001', null,
  'owner cannot just leave');
select lives_ok($$select public.transfer_ownership('f0000000-0000-0000-0000-00000000000f', 'bbbbbbbb-0000-0000-0000-000000000002')$$,
  'owner transfers ownership');
select lives_ok($$select public.leave_circle('f0000000-0000-0000-0000-00000000000f')$$,
  'former owner can now leave');

reset role;
select * from finish();
rollback;
