begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a@test.dev', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'b@test.dev', 'authenticated', 'authenticated');
insert into public.reminders (circle_id, created_by, title)
select id, owner_id, 'A thing' from public.circles where owner_id = 'aaaaaaaa-0000-0000-0000-000000000001';

create function pg_temp.login(uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.login(text) to authenticated;

set local role authenticated;
select pg_temp.login('aaaaaaaa-0000-0000-0000-000000000001');
select ok(public.request_account_deletion() > now() + interval '6 days', 'request schedules ~7 days out');
select is((select count(*)::int from public.account_deletions), 1, 'user sees their own pending deletion');
select throws_ok('select public.purge_deleted_accounts()', '42501', null, 'users cannot run the purge');
select lives_ok('select public.cancel_account_deletion()', 'user can cancel');
select is((select count(*)::int from public.account_deletions), 0, 'cancelled');
select public.request_account_deletion();

reset role;
select is(public.purge_deleted_accounts(), 0, 'nothing purged inside the grace period');
update public.account_deletions set purge_after = now() - interval '1 minute';
select is(public.purge_deleted_accounts(), 1, 'purged after the grace period');
select is((select count(*)::int from public.reminders where created_by = 'aaaaaaaa-0000-0000-0000-000000000001'), 0,
  'their data is gone (cascade)');

select * from finish();
rollback;
