-- Phase 7: subscriptions, trials, promo codes, entitlements, downgrade.
--
-- The Circle's plan (circles.plan_id) is *derived*: refresh_circle_plan()
-- picks the best entitled subscription, else Free. Only the server writes
-- subscriptions — via webhooks (apply_billing_event, service role) or the
-- owner-callable start_trial / redeem_promo RPCs. Members inherit the plan.

alter table public.subscriptions
  add column period               text check (period in ('month', 'year')),
  add column product_id           text,
  add column cancel_at_period_end boolean not null default false;
create unique index subscriptions_provider_ref
  on public.subscriptions (provider, external_ref) where external_ref is not null;

-- Billing history (receipts) + webhook idempotency.
create table public.billing_events (
  id              uuid primary key default gen_random_uuid(),
  circle_id       uuid not null references public.circles (id) on delete cascade,
  subscription_id uuid references public.subscriptions (id) on delete set null,
  provider        text not null,
  event_id        text not null,
  type            text not null,     -- purchase | renewal | trial_started | canceled | expired | billing_issue | promo | product_change | uncanceled
  plan_code       text,
  amount_inr      numeric(10, 2),
  occurred_at     timestamptz not null default now(),
  raw             jsonb,
  unique (provider, event_id)
);
create index billing_events_circle_idx on public.billing_events (circle_id, occurred_at desc);
alter table public.billing_events enable row level security;
create policy billing_events_select on public.billing_events for select to authenticated
  using (public.has_circle_role(circle_id, array['owner']::public.member_role[]));

create table public.promo_codes (
  code             text primary key check (code = upper(code)),
  plan_id          uuid not null references public.plans (id),
  days             int  not null check (days > 0),
  max_redemptions  int,
  redemptions      int  not null default 0,
  expires_at       timestamptz,
  is_active        boolean not null default true,
  note             text
);
alter table public.promo_codes enable row level security;  -- no client policies

create table public.promo_redemptions (
  code        text not null references public.promo_codes (code) on delete cascade,
  circle_id   uuid not null references public.circles (id) on delete cascade,
  user_id     uuid references public.users (id) on delete set null,
  redeemed_at timestamptz not null default now(),
  primary key (code, circle_id)
);
alter table public.promo_redemptions enable row level security;

-- ----------------------------------------------------------- entitlement
-- A subscription entitles until its period (or trial) ends. Canceled =
-- won't renew but still paid up; past_due = store grace period.
create function public.subscription_entitles(s public.subscriptions)
returns boolean language sql immutable as $$
  select s.status in ('trialing', 'active', 'past_due', 'canceled')
     and coalesce(s.current_period_end, s.trial_end) > now();
$$;

create function public.refresh_circle_plan(p_circle uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_plan uuid;
begin
  select s.plan_id into v_plan
    from public.subscriptions s join public.plans p on p.id = s.plan_id
   where s.circle_id = p_circle and public.subscription_entitles(s)
   order by p.sort desc, coalesce(s.current_period_end, s.trial_end) desc
   limit 1;
  v_plan := coalesce(v_plan, public.free_plan_id());
  -- Definer context: circles_guard lets the server change plan_id. Seats
  -- above the new limit are kept (graceful); only new joins are blocked.
  update public.circles set plan_id = v_plan
   where id = p_circle and plan_id is distinct from v_plan;
  return v_plan;
end $$;

create function public.subscriptions_refresh() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.refresh_circle_plan(coalesce(new.circle_id, old.circle_id));
  return coalesce(new, old);
end $$;
create trigger subscriptions_refresh after insert or update or delete on public.subscriptions
  for each row execute function public.subscriptions_refresh();

-- Personal plan fits a personal circle; Family/Team need a shared one.
create function public.plan_fits_circle(p_plan_code text, p_circle_type public.circle_type)
returns boolean language sql immutable as $$
  select case p_plan_code
    when 'personal' then p_circle_type = 'personal'
    when 'family'   then p_circle_type in ('family', 'team')
    when 'team'     then p_circle_type in ('family', 'team')
    else false end;
$$;

-- ------------------------------------------------------------ owner RPCs
create function public.start_trial(p_circle uuid, p_plan text)
returns timestamptz language plpgsql security definer set search_path = '' as $$
declare
  v_circle public.circles;
  v_plan   public.plans;
  v_end    timestamptz;
begin
  select * into v_circle from public.circles where id = p_circle;
  if v_circle.id is null or v_circle.owner_id <> (select auth.uid()) then
    raise exception 'only the owner can start a trial' using errcode = '42501';
  end if;
  select * into v_plan from public.plans where code = p_plan and is_active;
  if v_plan.id is null or v_plan.trial_days <= 0 then
    raise exception 'no trial for this plan' using errcode = 'P0001', hint = 'no_trial';
  end if;
  if not public.plan_fits_circle(p_plan, v_circle.type) then
    raise exception 'plan does not fit this circle' using errcode = 'P0001', hint = 'wrong_circle';
  end if;
  if exists (select 1 from public.subscriptions where circle_id = p_circle and trial_end is not null) then
    raise exception 'trial already used' using errcode = 'P0001', hint = 'trial_used';
  end if;
  v_end := now() + make_interval(days => v_plan.trial_days);
  insert into public.subscriptions (circle_id, plan_id, provider, status, trial_end, external_ref)
  values (p_circle, v_plan.id, 'manual', 'trialing', v_end, 'trial:' || p_circle);
  insert into public.billing_events (circle_id, provider, event_id, type, plan_code)
  values (p_circle, 'manual', 'trial:' || p_circle, 'trial_started', p_plan);
  return v_end;
end $$;

create function public.redeem_promo(p_circle uuid, p_code text)
returns timestamptz language plpgsql security definer set search_path = '' as $$
declare
  v_circle public.circles;
  v_promo  public.promo_codes;
  v_plan   public.plans;
  v_end    timestamptz;
  v_code   text := upper(trim(p_code));
begin
  select * into v_circle from public.circles where id = p_circle;
  if v_circle.id is null or v_circle.owner_id <> (select auth.uid()) then
    raise exception 'only the owner can redeem a code' using errcode = '42501';
  end if;
  select * into v_promo from public.promo_codes where code = v_code for update;
  if v_promo.code is null or not v_promo.is_active
     or (v_promo.expires_at is not null and v_promo.expires_at < now()) then
    raise exception 'promo code not valid' using errcode = 'P0001', hint = 'invalid_code';
  end if;
  if v_promo.max_redemptions is not null and v_promo.redemptions >= v_promo.max_redemptions then
    raise exception 'promo code used up' using errcode = 'P0001', hint = 'code_used_up';
  end if;
  select * into v_plan from public.plans where id = v_promo.plan_id;
  if not public.plan_fits_circle(v_plan.code, v_circle.type) then
    raise exception 'plan does not fit this circle' using errcode = 'P0001', hint = 'wrong_circle';
  end if;
  if exists (select 1 from public.promo_redemptions where code = v_code and circle_id = p_circle) then
    raise exception 'promo code already redeemed' using errcode = 'P0001', hint = 'already_redeemed';
  end if;
  v_end := now() + make_interval(days => v_promo.days);
  insert into public.promo_redemptions (code, circle_id, user_id) values (v_code, p_circle, (select auth.uid()));
  update public.promo_codes set redemptions = redemptions + 1 where code = v_code;
  insert into public.subscriptions (circle_id, plan_id, provider, status, current_period_end, external_ref, cancel_at_period_end)
  values (p_circle, v_plan.id, 'manual', 'active', v_end, 'promo:' || v_code || ':' || p_circle, true);
  insert into public.billing_events (circle_id, provider, event_id, type, plan_code, amount_inr)
  values (p_circle, 'manual', 'promo:' || v_code || ':' || p_circle, 'promo', v_plan.code, 0);
  return v_end;
end $$;

-- What the Subscription screen shows for one circle (members can read).
create function public.circle_billing(p_circle uuid)
returns table (plan_code text, status public.subscription_status, provider text,
               period text, current_period_end timestamptz, trial_end timestamptz,
               cancel_at_period_end boolean, trial_used boolean, seats_used int, max_seats int)
language sql stable security definer set search_path = '' as $$
  select p.code,
         s.status, s.provider, s.period, s.current_period_end, s.trial_end,
         coalesce(s.cancel_at_period_end, false),
         exists (select 1 from public.subscriptions t where t.circle_id = c.id and t.trial_end is not null),
         (select count(*)::int from public.memberships m where m.circle_id = c.id and m.status = 'active'),
         p.max_seats
    from public.circles c
    join public.plans p on p.id = c.plan_id
    left join lateral (
      select * from public.subscriptions s
       where s.circle_id = c.id and public.subscription_entitles(s)
       order by coalesce(s.current_period_end, s.trial_end) desc limit 1) s on true
   where c.id = p_circle and public.is_circle_member(c.id);
$$;

-- ------------------------------------------------------------- webhooks
-- Normalised event from an Edge Function that already verified the
-- provider's signature. Idempotent per (provider, event_id).
create function public.apply_billing_event(e jsonb)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_circle public.circles;
  v_plan   public.plans;
  v_sub    uuid;
  v_status public.subscription_status := (e->>'status')::public.subscription_status;
begin
  if exists (select 1 from public.billing_events
              where provider = e->>'provider' and event_id = e->>'event_id') then
    return 'duplicate';
  end if;
  select * into v_circle from public.circles where id = (e->>'circle_id')::uuid;
  if v_circle.id is null then return 'unknown_circle'; end if;
  -- The purchaser must own the circle (RevenueCat app_user_id = user id).
  if e ? 'user_id' and (e->>'user_id')::uuid is distinct from v_circle.owner_id then
    return 'not_owner';
  end if;
  select * into v_plan from public.plans where code = e->>'plan_code';
  if v_plan.id is null then return 'unknown_plan'; end if;

  insert into public.subscriptions as s
    (circle_id, plan_id, provider, status, current_period_end, trial_end,
     external_ref, period, product_id, cancel_at_period_end)
  values (v_circle.id, v_plan.id, e->>'provider', v_status,
          (e->>'current_period_end')::timestamptz, (e->>'trial_end')::timestamptz,
          e->>'external_ref', e->>'period', e->>'product_id',
          coalesce((e->>'cancel_at_period_end')::boolean, false))
  on conflict (provider, external_ref) where external_ref is not null do update set
    plan_id = excluded.plan_id,
    status = excluded.status,
    current_period_end = coalesce(excluded.current_period_end, s.current_period_end),
    -- trial_end is sticky: once a circle trialled, it stays recorded.
    trial_end = coalesce(s.trial_end, excluded.trial_end),
    period = coalesce(excluded.period, s.period),
    product_id = coalesce(excluded.product_id, s.product_id),
    cancel_at_period_end = excluded.cancel_at_period_end
  returning id into v_sub;

  insert into public.billing_events
    (circle_id, subscription_id, provider, event_id, type, plan_code, amount_inr, occurred_at, raw)
  values (v_circle.id, v_sub, e->>'provider', e->>'event_id', e->>'type', v_plan.code,
          (e->>'amount_inr')::numeric, coalesce((e->>'occurred_at')::timestamptz, now()), e->'raw');
  return 'ok';
end $$;

-- --------------------------------------------------- expiry (pg_cron)
create function public.expire_subscriptions()
returns int language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  update public.subscriptions s set status = 'expired'
   where s.status <> 'expired'
     and coalesce(s.current_period_end, s.trial_end) <= now();
  get diagnostics n = row_count;  -- the trigger refreshes each circle's plan
  return n;
end $$;
select cron.schedule('aria-expire-subscriptions', '*/15 * * * *',
                     'select public.expire_subscriptions()');

-- ------------------------------------------------------------- grants
revoke execute on function public.apply_billing_event(jsonb),
                           public.expire_subscriptions(),
                           public.refresh_circle_plan(uuid)
  from anon, authenticated, public;
grant execute on function public.apply_billing_event(jsonb) to service_role;
revoke execute on function public.start_trial(uuid, text),
                           public.redeem_promo(uuid, text),
                           public.circle_billing(uuid)
  from anon, public;
grant execute on function public.start_trial(uuid, text),
                          public.redeem_promo(uuid, text),
                          public.circle_billing(uuid)
  to authenticated;
