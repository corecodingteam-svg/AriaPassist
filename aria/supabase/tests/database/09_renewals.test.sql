begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

-- Owners: o1 (personal promo), o2 (family trial + member m2), o3 (auto-renew),
-- o4 (family ended today + member m4), o5 (ended 3.5 days ago), o6 (past_due),
-- o7 (renewed). o1 also opted in to WhatsApp.
insert into auth.users (id, email, aud, role, raw_user_meta_data)
select ('00000000-0000-0000-0000-0000000000' || lpad(i::text, 2, '0'))::uuid,
       'u' || i || '@t.dev', 'authenticated', 'authenticated', jsonb_build_object('name', 'U' || i)
  from generate_series(1, 9) i;

create temp table ids (k text primary key, id uuid);
insert into ids values
  ('o1', '00000000-0000-0000-0000-000000000001'), ('o2', '00000000-0000-0000-0000-000000000002'),
  ('o3', '00000000-0000-0000-0000-000000000003'), ('o4', '00000000-0000-0000-0000-000000000004'),
  ('o5', '00000000-0000-0000-0000-000000000005'), ('o6', '00000000-0000-0000-0000-000000000006'),
  ('o7', '00000000-0000-0000-0000-000000000007'), ('m2', '00000000-0000-0000-0000-000000000008'),
  ('m4', '00000000-0000-0000-0000-000000000009');

create function pg_temp.uid(k text) returns uuid language sql as $$ select id from ids where ids.k = $1 $$;
create function pg_temp.plan(c text) returns uuid language sql as $$ select id from public.plans where code = c $$;
create function pg_temp.personal(k text) returns uuid language sql as $$
  select id from public.circles where owner_id = pg_temp.uid(k) and type = 'personal' $$;
create function pg_temp.family(k text) returns uuid language sql as $$
  insert into public.circles (name, type, owner_id) values ('Fam ' || k, 'family', pg_temp.uid(k)) returning id $$;

create temp table fam (k text, id uuid);
insert into fam select k, pg_temp.family(k) from (values ('o2'), ('o4'), ('o5'), ('o6')) v(k);
update public.circles set plan_id = pg_temp.plan('family') where id in (select id from fam);
insert into public.memberships (circle_id, user_id, role, status) values
  ((select id from fam where k = 'o2'), pg_temp.uid('m2'), 'member', 'active'),
  ((select id from fam where k = 'o4'), pg_temp.uid('m4'), 'member', 'active');

insert into public.subscriptions (circle_id, plan_id, provider, status, current_period_end, trial_end, cancel_at_period_end, external_ref) values
  (pg_temp.personal('o1'), pg_temp.plan('personal'), 'manual', 'active', now() + interval '6 days 12 hours', null, true, 'p1'),
  ((select id from fam where k = 'o2'), pg_temp.plan('family'), 'manual', 'trialing', null, now() + interval '2 days 12 hours', false, 't2'),
  (pg_temp.personal('o3'), pg_temp.plan('personal'), 'revenuecat', 'active', now() + interval '2 days 12 hours', null, false, 'r3'),
  ((select id from fam where k = 'o4'), pg_temp.plan('family'), 'revenuecat', 'expired', now() - interval '12 hours', null, true, 'r4'),
  ((select id from fam where k = 'o5'), pg_temp.plan('family'), 'manual', 'expired', now() - interval '3 days 12 hours', null, true, 'p5'),
  ((select id from fam where k = 'o6'), pg_temp.plan('family'), 'revenuecat', 'past_due', now() + interval '5 days', null, false, 'r6'),
  (pg_temp.personal('o7'), pg_temp.plan('personal'), 'manual', 'expired', now() - interval '12 hours', null, true, 'p7a'),
  (pg_temp.personal('o7'), pg_temp.plan('personal'), 'revenuecat', 'active', now() + interval '30 days', null, false, 'r7b');

insert into public.whatsapp_optins (user_id, phone_e164) values (pg_temp.uid('o1'), '+919800000001');

select is(public.renewal_step(now() + interval '6 days 1 hour', false, 'active', now()), 'd7', 'step: 7 days');
select is(public.renewal_step(now() + interval '5 days', false, 'active', now()), null, 'step: nothing on day 5');
select is(public.renewal_step(now() + interval '2 days 1 hour', true, 'active', now()), 'courtesy', 'step: auto-renew courtesy');

create temp table c1 as select * from public.claim_renewal_notices(now(), 500);

select is((select array_agg(channel order by channel) from c1 where user_id = pg_temp.uid('o1')),
  array['email', 'whatsapp'], 'promo ending in 7 days: email + WhatsApp (opted in)');
select is((select distinct step from c1 where user_id = pg_temp.uid('o1')), 'd7', 'o1 gets the 7-day reminder');
select is((select step from c1 where user_id = pg_temp.uid('o2')), 'd3', 'trial ending in 3 days → d3 to owner');
select is((select count(*)::int from c1 where user_id = pg_temp.uid('m2')), 0, 'members are not reminded before the end');
select is((select step from c1 where user_id = pg_temp.uid('o3')), 'courtesy', 'auto-renewing plan → courtesy only');
select is((select array_agg(user_id order by user_id)::text from c1 where step = 'd0'),
  array[pg_temp.uid('o4'), pg_temp.uid('m4')]::text, 'ended today → owner and member');
select is((select step from c1 where user_id = pg_temp.uid('o5')), 'p3', 'ended 3 days ago → win-back');
select is((select step from c1 where user_id = pg_temp.uid('o6')), 'payment_issue', 'failed renewal payment → update payment');
select is((select count(*)::int from c1 where user_id = pg_temp.uid('o7')), 0, 'renewed → nothing');
select is((select count(*)::int from public.claim_renewal_notices(now(), 500)), 0, 'each notice is sent only once');

select lives_ok($$select public.record_renewal_notice((select notice_id from c1 limit 1), 'logged', null)$$, 'record result');

-- The app's billing view: auto-renew flag and the recently lapsed plan.
select set_config('request.jwt.claims', json_build_object('sub', pg_temp.uid('o3'), 'role', 'authenticated')::text, true);
select is((select auto_renews from public.circle_billing(pg_temp.personal('o3'))), true, 'billing view: auto-renews');
select set_config('request.jwt.claims', json_build_object('sub', pg_temp.uid('o5'), 'role', 'authenticated')::text, true);
update public.circles set plan_id = pg_temp.plan('free') where id = (select id from fam where k = 'o5');
select is((select lapsed_plan_code from public.circle_billing((select id from fam where k = 'o5'))), 'family',
  'billing view: lapsed Family plan');

select * from finish();
rollback;
