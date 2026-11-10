begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a@test.dev', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'b@test.dev', 'authenticated', 'authenticated');

create function pg_temp.login(uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.login(text) to authenticated;

set local role authenticated;
select pg_temp.login('aaaaaaaa-0000-0000-0000-000000000001');
select lives_ok($$
  insert into public.people (circle_id, created_by, name, birthday, call_every_days)
  select id, 'aaaaaaaa-0000-0000-0000-000000000001', 'Dad', '1958-03-14', 14
  from public.circles where owner_id = 'aaaaaaaa-0000-0000-0000-000000000001'
$$, 'A adds a person');

insert into public.notes (id, circle_id, created_by, text, embedding)
select 'a1000000-0000-0000-0000-00000000000a', id, 'aaaaaaaa-0000-0000-0000-000000000001',
       'Wifi password is sunflower42', array_fill(0.1, array[384])::extensions.vector
from public.circles where owner_id = 'aaaaaaaa-0000-0000-0000-000000000001';

select is((select count(*)::int from public.match_notes(array_fill(0.1, array[384])::extensions.vector, 5)), 1,
  'match_notes finds own note');

reset role;
-- now() is constant inside a transaction, so pin a sentinel timestamp first.
alter table public.notes disable trigger set_updated_at;
update public.notes set updated_at = '2000-01-01T00:00:00Z' where id = 'a1000000-0000-0000-0000-00000000000a';
alter table public.notes enable trigger set_updated_at;
-- embedding-only update keeps updated_at (no sync churn)
select set_config('aria.before', (select updated_at::text from public.notes where id = 'a1000000-0000-0000-0000-00000000000a'), true);
update public.notes set embedding = array_fill(0.2, array[384])::extensions.vector
  where id = 'a1000000-0000-0000-0000-00000000000a';
select is((select updated_at::text from public.notes where id = 'a1000000-0000-0000-0000-00000000000a'),
  current_setting('aria.before'), 'embedding writes do not bump updated_at');
update public.notes set text = 'Wifi password is tulip7' where id = 'a1000000-0000-0000-0000-00000000000a';
select isnt((select updated_at::text from public.notes where id = 'a1000000-0000-0000-0000-00000000000a'),
  current_setting('aria.before'), 'real edits still bump updated_at');

create temp table a_circle as
  select id from public.circles where owner_id = 'aaaaaaaa-0000-0000-0000-000000000001';
grant select on a_circle to authenticated;
set local role authenticated;
select pg_temp.login('bbbbbbbb-0000-0000-0000-000000000002');
select is((select count(*)::int from public.people), 0, 'B cannot see A''s people');
select is((select count(*)::int from public.match_notes(array_fill(0.1, array[384])::extensions.vector, 5)), 0,
  'semantic search respects RLS');
select throws_ok($$
  insert into public.people (circle_id, created_by, name)
  select id, 'bbbbbbbb-0000-0000-0000-000000000002', 'x' from a_circle
$$, '42501', null, 'B cannot add people to A''s circle');

reset role;
select ok((select count(*) from pg_publication_tables where pubname = 'supabase_realtime'
           and tablename in ('lists', 'list_items', 'notes', 'reminders', 'people')) = 5,
  'shared tables publish realtime changes');

select * from finish();
rollback;
