begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

insert into auth.users (id, phone, aud, role, raw_user_meta_data) values
  ('aaaaaaaa-0000-0000-0000-0000000000a7', '919811111111', 'authenticated', 'authenticated', '{"name":"Asha"}'),
  ('bbbbbbbb-0000-0000-0000-0000000000b7', '919822222222', 'authenticated', 'authenticated', '{"name":"Bala"}');
insert into auth.users (id, email, aud, role) values
  ('cccccccc-0000-0000-0000-0000000000c7', 'mail@t.dev', 'authenticated', 'authenticated');

create function pg_temp.login(uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.login(text) to authenticated;

create temp table pc as
  select owner_id as uid, id from public.circles where type = 'personal'
    and owner_id in ('aaaaaaaa-0000-0000-0000-0000000000a7', 'bbbbbbbb-0000-0000-0000-0000000000b7',
                     'cccccccc-0000-0000-0000-0000000000c7');

-- Free plan → no WhatsApp.
set local role authenticated;
select pg_temp.login('aaaaaaaa-0000-0000-0000-0000000000a7');
select throws_like($$select public.set_whatsapp(true)$$, '%Family or Team%', 'free plan cannot enable WhatsApp');
reset role;

-- Family plan (billing) for Asha's and the email user's circles.
insert into public.circles (id, name, type, owner_id)
values ('f7000000-0000-0000-0000-0000000000f7', 'Home', 'family', 'aaaaaaaa-0000-0000-0000-0000000000a7'),
       ('f8000000-0000-0000-0000-0000000000f8', 'Mail', 'family', 'cccccccc-0000-0000-0000-0000000000c7');
update public.circles set plan_id = (select id from public.plans where code = 'family')
 where id in ('f7000000-0000-0000-0000-0000000000f7', 'f8000000-0000-0000-0000-0000000000f8');

set local role authenticated;
select pg_temp.login('aaaaaaaa-0000-0000-0000-0000000000a7');
select is(public.set_whatsapp(true), '+919811111111', 'opt-in uses the verified sign-in phone');
select is((select count(*)::int from public.whatsapp_optins), 1, 'user sees their own opt-in');
select pg_temp.login('cccccccc-0000-0000-0000-0000000000c7');
select throws_like($$select public.set_whatsapp(true)$$, '%phone number%', 'email-only accounts need a phone');
select throws_ok($$select * from public.claim_whatsapp_due(10)$$, '42501', null, 'clients cannot claim messages');
reset role;

-- Reminders: due now (Asha), due 20 min ago (too old), Bala (not opted in), recurring.
insert into public.reminders (id, circle_id, created_by, title, start_at, timezone, amount, rrule) values
  ('a1000000-0000-0000-0000-000000000001', 'f7000000-0000-0000-0000-0000000000f7',
   'aaaaaaaa-0000-0000-0000-0000000000a7', 'Pay rent', now() - interval '1 minute', 'Asia/Kolkata', 25000, null),
  ('a1000000-0000-0000-0000-000000000002', 'f7000000-0000-0000-0000-0000000000f7',
   'aaaaaaaa-0000-0000-0000-0000000000a7', 'Old one', now() - interval '20 minutes', 'Asia/Kolkata', null, null),
  ('a1000000-0000-0000-0000-000000000003', (select id from pc where uid = 'bbbbbbbb-0000-0000-0000-0000000000b7'),
   'bbbbbbbb-0000-0000-0000-0000000000b7', 'Bala thing', now() - interval '1 minute', 'Asia/Kolkata', null, null),
  ('a1000000-0000-0000-0000-000000000004', 'f7000000-0000-0000-0000-0000000000f7',
   'aaaaaaaa-0000-0000-0000-0000000000a7', 'Vitamin D', now() - interval '2 minutes', 'Asia/Kolkata', null, 'FREQ=DAILY');

select is((select array_agg(title order by title) from public.claim_whatsapp_due(10)),
  array['Pay rent', 'Vitamin D'], 'claims recent due reminders of opted-in users only');
select is((select count(*)::int from public.claim_whatsapp_due(10)), 0, 'never twice for the same occurrence');
select is((select phone_e164 from public.whatsapp_outbox where reminder_id = 'a1000000-0000-0000-0000-000000000001'),
  '+919811111111', 'sent to the opted-in number');

-- Send results + replies.
select public.record_whatsapp_send(id, 'sent', 'wamid.RENT', null)
  from public.whatsapp_outbox where reminder_id = 'a1000000-0000-0000-0000-000000000001';
select public.record_whatsapp_send(id, 'sent', 'wamid.VIT', null)
  from public.whatsapp_outbox where reminder_id = 'a1000000-0000-0000-0000-000000000004';
select is(public.apply_whatsapp_inbound(null, null, null, 'read', 'wamid.RENT'), 'status', 'receipt recorded');
select is((select status from public.whatsapp_outbox where wamid = 'wamid.RENT'), 'read', 'status is read');
select is(public.apply_whatsapp_inbound('919811111111', 'wamid.RENT', 'what?', null, null), 'ignored', 'chatter ignored');
select is(public.apply_whatsapp_inbound('919811111111', 'wamid.RENT', 'Done!', null, null), 'done', '"Done" on the message');
select is((select status::text from public.reminders where id = 'a1000000-0000-0000-0000-000000000001'), 'done',
  'one-off reminder completed');
select is(public.apply_whatsapp_inbound('919811111111', 'wamid.VIT', 'ho gaya', null, null), 'done',
  'Hinglish reply works');
select is((select status::text || '/' || (last_done_at is not null)::text from public.reminders
            where id = 'a1000000-0000-0000-0000-000000000004'),
  'active/true', 'recurring: marked done, stays active for the app to advance');
select is((select count(*)::int from public.reminder_events where meta_json->>'via' = 'whatsapp'), 2,
  'done events logged');

select * from finish();
rollback;
