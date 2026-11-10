begin;
create extension if not exists pgtap with schema extensions;
select plan(27);

insert into auth.users (id, email, aud, role, raw_user_meta_data) values
  ('aaaaaaaa-0000-0000-0000-00000000000a', 'own@t.dev', 'authenticated', 'authenticated', '{"name":"Owner"}'),
  ('bbbbbbbb-0000-0000-0000-00000000000b', 'mem@t.dev', 'authenticated', 'authenticated', '{"name":"Mem"}'),
  ('cccccccc-0000-0000-0000-00000000000c', 'new@t.dev', 'authenticated', 'authenticated', '{"name":"New"}');

create function pg_temp.login(uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.login(text) to authenticated;
create function pg_temp.plan_of(c uuid) returns text language sql security definer as $$
  select p.code from public.circles x join public.plans p on p.id = x.plan_id where x.id = c;
$$;
grant execute on function pg_temp.plan_of(uuid) to authenticated;

set local role authenticated;
select pg_temp.login('aaaaaaaa-0000-0000-0000-00000000000a');
insert into public.circles (id, name, type, owner_id)
values ('f1000000-0000-0000-0000-0000000000f1', 'Home', 'family', 'aaaaaaaa-0000-0000-0000-00000000000a');
reset role;
create temp table personal as
  select id from public.circles where owner_id = 'aaaaaaaa-0000-0000-0000-00000000000a' and type = 'personal';
grant select on personal to authenticated;

select is(pg_temp.plan_of('f1000000-0000-0000-0000-0000000000f1'), 'free', 'new circle starts on Free');

-- Trials ------------------------------------------------------------------
set local role authenticated;
select pg_temp.login('bbbbbbbb-0000-0000-0000-00000000000b');
select throws_ok($$select public.start_trial('f1000000-0000-0000-0000-0000000000f1', 'family')$$,
  '42501', null, 'non-owner cannot start a trial');

select pg_temp.login('aaaaaaaa-0000-0000-0000-00000000000a');
select throws_like($$select public.start_trial('f1000000-0000-0000-0000-0000000000f1', 'personal')$$,
  '%does not fit%', 'Personal plan does not fit a family circle');
select ok(public.start_trial('f1000000-0000-0000-0000-0000000000f1', 'family') > now() + interval '6 days',
  'owner starts a 7-day Family trial');
select is(pg_temp.plan_of('f1000000-0000-0000-0000-0000000000f1'), 'family', 'trial upgrades the circle plan');
select throws_like($$select public.start_trial('f1000000-0000-0000-0000-0000000000f1', 'team')$$,
  '%trial already used%', 'one trial per circle');
select is((select plan_code || '/' || status || '/' || trial_used || '/' || max_seats
             from public.circle_billing('f1000000-0000-0000-0000-0000000000f1')),
  'family/trialing/true/5', 'circle_billing reports the trial');
select throws_ok($$insert into public.subscriptions (circle_id, plan_id, provider, status)
                   select 'f1000000-0000-0000-0000-0000000000f1', id, 'manual', 'active' from public.plans where code = 'team'$$,
  '42501', null, 'clients cannot write subscriptions');
select throws_ok($$select public.apply_billing_event('{}'::jsonb)$$,
  '42501', null, 'clients cannot call the webhook function');
reset role;

-- With Family seats a second person can join.
insert into public.memberships (circle_id, user_id, role, status)
values ('f1000000-0000-0000-0000-0000000000f1', 'bbbbbbbb-0000-0000-0000-00000000000b', 'member', 'active');
set local role authenticated;
select pg_temp.login('bbbbbbbb-0000-0000-0000-00000000000b');
select is((select plan_code from public.circle_billing('f1000000-0000-0000-0000-0000000000f1')),
  'family', 'members see the plan they inherit');
select is((select count(*)::int from public.billing_events), 0, 'members cannot see billing history');
select pg_temp.login('cccccccc-0000-0000-0000-00000000000c');
select is((select count(*)::int from public.circle_billing('f1000000-0000-0000-0000-0000000000f1')), 0,
  'outsiders see nothing');
select pg_temp.login('aaaaaaaa-0000-0000-0000-00000000000a');
select is((select type from public.billing_events), 'trial_started', 'owner sees billing history');
reset role;

-- Expiry → graceful downgrade ---------------------------------------------
update public.subscriptions set trial_end = now() - interval '1 second'
 where circle_id = 'f1000000-0000-0000-0000-0000000000f1';
select is(public.expire_subscriptions(), 1, 'cron expires the ended trial');
select is(pg_temp.plan_of('f1000000-0000-0000-0000-0000000000f1'), 'free', 'circle falls back to Free');
select is((select count(*)::int from public.memberships
            where circle_id = 'f1000000-0000-0000-0000-0000000000f1' and status = 'active'), 2,
  'existing members are kept');
select throws_like($$insert into public.memberships (circle_id, user_id, role, status)
                     values ('f1000000-0000-0000-0000-0000000000f1', 'cccccccc-0000-0000-0000-00000000000c', 'member', 'active')$$,
  '%seat limit%', 'new joins are blocked over the limit');

-- Webhooks ----------------------------------------------------------------
select is(public.apply_billing_event(jsonb_build_object(
  'provider', 'revenuecat', 'event_id', 'evt-1', 'type', 'purchase',
  'circle_id', 'f1000000-0000-0000-0000-0000000000f1', 'user_id', 'aaaaaaaa-0000-0000-0000-00000000000a',
  'plan_code', 'family', 'period', 'month', 'status', 'active', 'amount_inr', 199,
  'external_ref', 'GPA.1', 'current_period_end', now() + interval '30 days')), 'ok', 'purchase applied');
select is(pg_temp.plan_of('f1000000-0000-0000-0000-0000000000f1'), 'family', 'purchase upgrades');
select is(public.apply_billing_event(jsonb_build_object(
  'provider', 'revenuecat', 'event_id', 'evt-1', 'type', 'purchase',
  'circle_id', 'f1000000-0000-0000-0000-0000000000f1', 'plan_code', 'family', 'status', 'active')),
  'duplicate', 'webhook retries are idempotent');
select is(public.apply_billing_event(jsonb_build_object(
  'provider', 'revenuecat', 'event_id', 'evt-x', 'type', 'purchase',
  'circle_id', 'f1000000-0000-0000-0000-0000000000f1', 'user_id', 'bbbbbbbb-0000-0000-0000-00000000000b',
  'plan_code', 'team', 'status', 'active', 'external_ref', 'GPA.2')),
  'not_owner', 'only the owner''s purchase counts for a circle');
select is(public.apply_billing_event(jsonb_build_object(
  'provider', 'revenuecat', 'event_id', 'evt-2', 'type', 'canceled',
  'circle_id', 'f1000000-0000-0000-0000-0000000000f1', 'plan_code', 'family', 'status', 'canceled',
  'external_ref', 'GPA.1', 'cancel_at_period_end', true)) || '/' ||
  pg_temp.plan_of('f1000000-0000-0000-0000-0000000000f1'),
  'ok/family', 'cancel keeps the plan until the period ends');
select is(public.apply_billing_event(jsonb_build_object(
  'provider', 'revenuecat', 'event_id', 'evt-3', 'type', 'expired',
  'circle_id', 'f1000000-0000-0000-0000-0000000000f1', 'plan_code', 'family', 'status', 'expired',
  'external_ref', 'GPA.1')) || '/' || pg_temp.plan_of('f1000000-0000-0000-0000-0000000000f1'),
  'ok/free', 'expiration downgrades');

-- Promo codes -------------------------------------------------------------
insert into public.promo_codes (code, plan_id, days, max_redemptions)
select 'TESTMONTH', id, 30, 1 from public.plans where code = 'personal';
set local role authenticated;
select pg_temp.login('aaaaaaaa-0000-0000-0000-00000000000a');
select throws_like($$select public.redeem_promo((select id from personal), 'nope')$$,
  '%not valid%', 'unknown code rejected');
select ok(public.redeem_promo((select id from personal), ' testmonth ') > now() + interval '29 days',
  'code redeemed (case/space-insensitive)');
select is(pg_temp.plan_of((select id from personal)), 'personal', 'promo grants the plan');
select throws_like($$select public.redeem_promo((select id from personal), 'TESTMONTH')$$,
  '%used up%', 'max redemptions enforced');
reset role;

select * from finish();
rollback;
