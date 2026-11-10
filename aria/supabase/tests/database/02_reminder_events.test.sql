-- Reminder lifecycle + events (Phase 2).
begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a@test.dev', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'b@test.dev', 'authenticated', 'authenticated');

insert into public.reminders (id, circle_id, created_by, title)
select 'a0000000-0000-0000-0000-00000000000a', c.id, c.owner_id, 'A pill'
from public.circles c where c.owner_id = 'aaaaaaaa-0000-0000-0000-000000000001';
insert into public.reminders (id, circle_id, created_by, title)
select 'b0000000-0000-0000-0000-00000000000b', c.id, c.owner_id, 'B pill'
from public.circles c where c.owner_id = 'bbbbbbbb-0000-0000-0000-000000000002';

create function pg_temp.login(uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.login(text) to authenticated;

set local role authenticated;
select pg_temp.login('aaaaaaaa-0000-0000-0000-000000000001');

select lives_ok($$
  update public.reminders
     set snoozed_until = now() + interval '15 minutes', last_done_at = now()
   where id = 'a0000000-0000-0000-0000-00000000000a'
$$, 'owner can snooze / complete (new lifecycle columns)');

select lives_ok($$
  insert into public.reminder_events (id, reminder_id, user_id, type, occurrence_at)
  values ('e0000000-0000-0000-0000-00000000000e', 'a0000000-0000-0000-0000-00000000000a',
          'aaaaaaaa-0000-0000-0000-000000000001', 'missed', now())
$$, 'A logs an event on their reminder');

select lives_ok($$
  insert into public.reminder_events (id, reminder_id, user_id, type, occurrence_at, meta_json)
  values ('e0000000-0000-0000-0000-00000000000e', 'a0000000-0000-0000-0000-00000000000a',
          'aaaaaaaa-0000-0000-0000-000000000001', 'missed', now(), '{"resolved": true}')
  on conflict (id) do update set meta_json = excluded.meta_json
$$, 'same deterministic id from another device upserts (no duplicate)');
select is((select count(*)::int from public.reminder_events), 1, 'still one row after upsert');
select is((select meta_json ->> 'resolved' from public.reminder_events), 'true', 'upsert applied');

select throws_ok($$
  insert into public.reminder_events (reminder_id, user_id, type)
  values ('b0000000-0000-0000-0000-00000000000b', 'aaaaaaaa-0000-0000-0000-000000000001', 'done')
$$, '42501', null, 'A cannot log events on B''s reminder');

select throws_ok($$
  insert into public.reminder_events (reminder_id, user_id, type)
  values ('a0000000-0000-0000-0000-00000000000a', 'bbbbbbbb-0000-0000-0000-000000000002', 'done')
$$, '42501', null, 'A cannot log events as B');

select throws_ok($$
  update public.reminder_events set reminder_id = 'b0000000-0000-0000-0000-00000000000b'
$$, '42501', null, 'events cannot be re-pointed at another reminder');

select pg_temp.login('bbbbbbbb-0000-0000-0000-000000000002');
select is((select count(*)::int from public.reminder_events), 0, 'B cannot see A''s events');

reset role;
select * from finish();
rollback;
