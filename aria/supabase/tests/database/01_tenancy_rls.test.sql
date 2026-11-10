-- Multi-tenant isolation tests. Run: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
select plan(37);

-- ---------------------------------------------------------------- fixtures
-- Fixed ids so assertions are readable. Inserting into auth.users fires the
-- real sign-up trigger, exactly as GoTrue does.
insert into auth.users (id, email, phone, raw_user_meta_data, aud, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a@test.dev', '919000000001', '{"name":"Asha"}', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'b@test.dev', '919000000002', '{"name":"Bala"}', 'authenticated', 'authenticated'),
  ('cccccccc-0000-0000-0000-000000000003', 'c@test.dev', '919000000003', '{"name":"Chitra"}', 'authenticated', 'authenticated');

create temp table ids as
select
  (select id from public.circles where owner_id = 'aaaaaaaa-0000-0000-0000-000000000001' and type = 'personal') as a_personal,
  (select id from public.circles where owner_id = 'bbbbbbbb-0000-0000-0000-000000000002' and type = 'personal') as b_personal;
grant select on ids to authenticated;

-- Login helper (claims are what auth.uid() reads).
create function pg_temp.login(uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.login(text) to authenticated;

-- ---------------------------------------------------- sign-up provisioning
select is((select count(*)::int from public.users where id = 'aaaaaaaa-0000-0000-0000-000000000001'), 1,
  'sign-up creates a users row');
select is((select name from public.users where id = 'aaaaaaaa-0000-0000-0000-000000000001'), 'Asha',
  'sign-up copies the name from metadata');
select isnt((select a_personal from ids), null, 'sign-up creates a personal circle');
select is((select role::text from public.memberships m, ids
           where m.circle_id = ids.a_personal and m.user_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'owner', 'creator is owner of the personal circle');
select is((select p.code from public.circles c join public.plans p on p.id = c.plan_id, ids where c.id = ids.a_personal),
  'free', 'personal circle starts on the free plan');
select is((select active_circle_id from public.user_settings where user_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  (select a_personal from ids), 'default settings point at the personal circle');

-- B owns a private reminder + list item in B's personal circle.
insert into public.reminders (id, circle_id, created_by, title)
select 'b0000000-0000-0000-0000-00000000000b', b_personal, 'bbbbbbbb-0000-0000-0000-000000000002', 'B secret' from ids;
insert into public.lists (id, circle_id, created_by, name)
select 'b1000000-0000-0000-0000-00000000000b', b_personal, 'bbbbbbbb-0000-0000-0000-000000000002', 'B list' from ids;
insert into public.list_items (list_id, text, added_by)
values ('b1000000-0000-0000-0000-00000000000b', 'B item', 'bbbbbbbb-0000-0000-0000-000000000002');

-- ============================================== as A: cross-tenant isolation
set local role authenticated;
select pg_temp.login('aaaaaaaa-0000-0000-0000-000000000001');

select is((select count(*)::int from public.circles), 1, 'A sees only their own circle');
select is((select count(*)::int from public.circles c, ids where c.id = ids.b_personal), 0,
  'A cannot see B''s circle');
select is((select count(*)::int from public.reminders), 0, 'A cannot read B''s reminders');
select is((select count(*)::int from public.lists), 0, 'A cannot read B''s lists');
select is((select count(*)::int from public.list_items), 0, 'A cannot read B''s list items');
select is((select count(*)::int from public.user_settings), 1, 'A sees only their own settings');
select is((select count(*)::int from public.users), 1, 'A cannot see users they share no circle with');
select is((select count(*)::int from public.memberships), 1, 'A sees only memberships of their circles');

select lives_ok($$
  insert into public.reminders (circle_id, created_by, title)
  select a_personal, 'aaaaaaaa-0000-0000-0000-000000000001', 'Drink water' from ids
$$, 'A can create a reminder in their own circle');

select throws_ok($$
  insert into public.reminders (circle_id, created_by, title)
  select b_personal, 'aaaaaaaa-0000-0000-0000-000000000001', 'sneaky' from ids
$$, '42501', null, 'A cannot insert into B''s circle');

select throws_ok($$
  insert into public.reminders (circle_id, created_by, title)
  select a_personal, 'bbbbbbbb-0000-0000-0000-000000000002', 'spoofed author' from ids
$$, '42501', null, 'A cannot spoof created_by');

with u as (update public.reminders set title = 'pwned'
                      where id = 'b0000000-0000-0000-0000-00000000000b' returning 1)
select is(count(*)::int, 0, 'A cannot update B''s reminder') from u;
with d as (delete from public.reminders
                      where id = 'b0000000-0000-0000-0000-00000000000b' returning 1)
select is(count(*)::int, 0, 'A cannot delete B''s reminder') from d;

select throws_ok($$
  update public.reminders set circle_id = (select b_personal from ids) where title = 'Drink water'
$$, '42501', null, 'A cannot move their reminder into B''s circle');

select throws_ok($$
  update public.circles set plan_id = (select id from public.plans where code = 'family')
  where id = (select a_personal from ids)
$$, '42501', null, 'client cannot upgrade their own plan');

select throws_ok($$
  insert into public.memberships (circle_id, user_id, role)
  select a_personal, 'bbbbbbbb-0000-0000-0000-000000000002', 'member' from ids
$$, '42501', null, 'personal circles cannot gain members');

select throws_ok($$
  insert into public.reminders (circle_id, created_by, assigned_to, title)
  select a_personal, 'aaaaaaaa-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002', 'assign out' from ids
$$, '42501', null, 'A cannot assign a reminder to a non-member');

-- A creates a family circle; client-supplied plan is overridden to free.
select lives_ok($$
  insert into public.circles (id, name, type, owner_id, plan_id)
  values ('f0000000-0000-0000-0000-00000000000f', 'Sharma family', 'family',
          'aaaaaaaa-0000-0000-0000-000000000001', (select id from public.plans where code = 'team'))
$$, 'A can create a family circle');
select is((select p.code from public.circles c join public.plans p on p.id = c.plan_id
           where c.id = 'f0000000-0000-0000-0000-00000000000f'), 'free',
  'client-chosen plan is ignored on insert');

select throws_ok($$
  insert into public.memberships (circle_id, user_id, role)
  values ('f0000000-0000-0000-0000-00000000000f', 'bbbbbbbb-0000-0000-0000-000000000002', 'member')
$$, 'P0001', null, 'free plan seat limit (1) blocks a second member');

-- ======================== billing webhook (service role) upgrades the circle
reset role;
update public.circles set plan_id = (select id from public.plans where code = 'family')
where id = 'f0000000-0000-0000-0000-00000000000f';

set local role authenticated;
select pg_temp.login('aaaaaaaa-0000-0000-0000-000000000001');
select lives_ok($$
  insert into public.memberships (circle_id, user_id, role) values
    ('f0000000-0000-0000-0000-00000000000f', 'bbbbbbbb-0000-0000-0000-000000000002', 'member')
$$, 'after upgrade, the owner can add a member');

insert into public.reminders (circle_id, created_by, title, visibility) values
  ('f0000000-0000-0000-0000-00000000000f', 'aaaaaaaa-0000-0000-0000-000000000001', 'Family dinner', 'shared'),
  ('f0000000-0000-0000-0000-00000000000f', 'aaaaaaaa-0000-0000-0000-000000000001', 'A private in family', 'private');

-- ====================================================== as B: inside circle
select pg_temp.login('bbbbbbbb-0000-0000-0000-000000000002');
select is((select count(*)::int from public.reminders where circle_id = 'f0000000-0000-0000-0000-00000000000f'), 1,
  'B sees the shared family reminder but not A''s private one');
select is((select count(*)::int from public.users), 2, 'B can see fellow circle members');

update public.memberships set role = 'admin'
where circle_id = 'f0000000-0000-0000-0000-00000000000f' and user_id = 'bbbbbbbb-0000-0000-0000-000000000002';
select is((select role::text from public.memberships
           where circle_id = 'f0000000-0000-0000-0000-00000000000f' and user_id = 'bbbbbbbb-0000-0000-0000-000000000002'),
  'member', 'B (member) cannot promote themselves');
with u as (update public.memberships set status = 'removed'
                      where circle_id = 'f0000000-0000-0000-0000-00000000000f' and role = 'owner' returning 1)
select is(count(*)::int, 0, 'nobody can remove the owner from the client') from u;

select is((select count(*)::int from public.audit_logs where circle_id = 'f0000000-0000-0000-0000-00000000000f'), 0,
  'members cannot read the circle''s audit log');

select pg_temp.login('aaaaaaaa-0000-0000-0000-000000000001');
select ok((select count(*) from public.audit_logs where circle_id = 'f0000000-0000-0000-0000-00000000000f'
           and action = 'member.added') >= 2, 'owner sees member.added entries in the audit log');
select lives_ok($$ delete from public.circles where id = 'f0000000-0000-0000-0000-00000000000f' $$,
  'owner can delete a family circle (cascade + audit trigger are safe)');

-- ======================================================= C: outsider again
select pg_temp.login('cccccccc-0000-0000-0000-000000000003');
select is((select count(*)::int from public.reminders), 0, 'an outsider sees no reminders at all');

-- ================================================================= as anon
reset role;
set local role anon;
select is((select count(*)::int from public.plans), 4, 'anon can read plans (paywall before sign-in)');
select is((select count(*)::int from public.reminders), 0, 'anon reads no reminders');

reset role;
select * from finish();
rollback;
