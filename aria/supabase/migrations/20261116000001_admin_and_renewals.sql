-- Admin safety layer, account suspension, tenure/report views, and the
-- renewal-reminder schedule.
--
-- Principles
-- * Nobody hand-edits live rows: every admin change is a function that
--   validates, touches one thing, requires a reason and is logged in the
--   append-only admin_actions table.
-- * Admins see metadata, never reminder / note / list / place content.
-- * Suspension blocks everything server-side at once (PostgREST pre-request
--   hook + restrictive RLS) and stops sign-in (auth ban).

-- ============================================================== admins
create table public.admins (
  user_id    uuid primary key references public.users (id) on delete cascade,
  role       text not null check (role in ('super', 'support', 'finance')),
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security;
-- An admin can see their own role (the admin panel needs it); nothing else.
create policy admins_self on public.admins for select to authenticated
  using (user_id = (select auth.uid()));

-- Append-only log of every admin action.
create table public.admin_actions (
  id            uuid primary key default gen_random_uuid(),
  actor         text not null,        -- admin user id, or console:<name>
  action        text not null,
  target_user   uuid,                 -- no FK: the log outlives deletions
  target_circle uuid,
  reason        text not null check (length(trim(reason)) >= 3),
  details       jsonb not null default '{}'::jsonb,
  at            timestamptz not null default now()
);
create index admin_actions_at on public.admin_actions (at desc);
create index admin_actions_target on public.admin_actions (target_user);
alter table public.admin_actions enable row level security;  -- no client policies

create function public.admin_actions_append_only() returns trigger
language plpgsql as $$
begin
  raise exception 'admin_actions is append-only' using errcode = '42501';
end $$;
create trigger admin_actions_no_update before update or delete on public.admin_actions
  for each row execute function public.admin_actions_append_only();
create trigger admin_actions_no_truncate before truncate on public.admin_actions
  for each statement execute function public.admin_actions_append_only();

-- Who is calling? An admin through the API (role checked), or the database
-- console / service role (break-glass; name yourself with
--   select set_config('aria.actor', 'you@company', false);  ).
create function public.admin_actor(p_roles text[])
returns text language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid  uuid := auth.uid();
  v_role text;
begin
  if v_uid is not null then
    select role into v_role from public.admins where user_id = v_uid;
    if v_role is null or not (v_role = 'super' or v_role = any (p_roles)) then
      raise exception 'admin permission required' using errcode = '42501';
    end if;
    return v_uid::text;
  end if;
  if auth.role() = 'service_role' or session_user <> 'authenticator' then
    return 'console:' || coalesce(nullif(current_setting('aria.actor', true), ''), session_user);
  end if;
  raise exception 'admin permission required' using errcode = '42501';
end $$;

create function public.admin_log(p_actor text, p_action text, p_user uuid, p_circle uuid,
                                 p_reason text, p_details jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'a reason is required' using errcode = 'P0001', hint = 'reason_required';
  end if;
  insert into public.admin_actions (actor, action, target_user, target_circle, reason, details)
  values (p_actor, p_action, p_user, p_circle, trim(p_reason), coalesce(p_details, '{}'::jsonb));
end $$;

-- ========================================================== suspension
alter table public.users
  add column suspended_at     timestamptz,
  add column suspended_reason text,
  add column last_seen_at     timestamptz;

-- Clients may edit their profile, never their suspension.
create function public.users_guard_admin_fields() returns trigger
language plpgsql as $$
begin
  if public.is_client_request() and (
       new.suspended_at is distinct from old.suspended_at
    or new.suspended_reason is distinct from old.suspended_reason) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger users_guard_admin_fields before update on public.users
  for each row execute function public.users_guard_admin_fields();

create function public.is_suspended()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.users
                  where id = (select auth.uid()) and suspended_at is not null);
$$;

-- Runs before every API request (PostgREST pre-request): a suspended
-- account gets HTTP 403 for tables and functions alike.
create function public.check_request()
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if public.is_suspended() then
    raise sqlstate 'PT403' using message = 'account suspended', hint = 'suspended';
  end if;
end $$;
grant execute on function public.check_request() to anon, authenticated, service_role;
alter role authenticator set pgrst.db_pre_request = 'public.check_request';
notify pgrst, 'reload config';

-- Defence in depth (Realtime, any path that skips PostgREST): every
-- client-visible table also requires "not suspended".
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' and rowsecurity loop
    execute format(
      'create policy not_suspended on public.%I as restrictive for all to authenticated
         using ((select not public.is_suspended())) with check ((select not public.is_suspended()))', t);
  end loop;
end $$;

-- "Last seen" (at most hourly), for active-user reports.
create function public.touch_last_seen()
returns void language sql security definer set search_path = '' as $$
  update public.users set last_seen_at = now()
   where id = (select auth.uid())
     and (last_seen_at is null or last_seen_at < now() - interval '1 hour');
$$;

-- What the app checks on start/resume (blocked with 403 when suspended).
create function public.account_status()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('ok', true);
$$;

-- ===================================================== admin functions
create function public.admin_suspend_user(p_user uuid, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := public.admin_actor(array['support']);
  v_target_admin text;
begin
  if not exists (select 1 from public.users where id = p_user) then
    raise exception 'user not found' using errcode = 'P0002';
  end if;
  if p_user::text = v_actor then
    raise exception 'you cannot suspend yourself' using errcode = 'P0001', hint = 'self';
  end if;
  select role into v_target_admin from public.admins where user_id = p_user;
  if v_target_admin is not null
     and coalesce((select role from public.admins where user_id = auth.uid()), 'console') not in ('super', 'console') then
    raise exception 'only a super-admin can suspend an admin' using errcode = '42501';
  end if;
  perform public.admin_log(v_actor, 'user.suspended', p_user, null, p_reason);
  update public.users set suspended_at = coalesce(suspended_at, now()), suspended_reason = trim(p_reason)
   where id = p_user;
  -- No sign-in or token refresh, and every session ends.
  update auth.users set banned_until = '9999-12-31' where id = p_user;
  delete from auth.refresh_tokens where user_id = p_user::text;
  delete from auth.sessions where user_id = p_user;
end $$;

create function public.admin_unsuspend_user(p_user uuid, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_actor text := public.admin_actor(array['support']);
begin
  if not exists (select 1 from public.users where id = p_user and suspended_at is not null) then
    raise exception 'user is not suspended' using errcode = 'P0001', hint = 'not_suspended';
  end if;
  perform public.admin_log(v_actor, 'user.unsuspended', p_user, null, p_reason);
  update public.users set suspended_at = null, suspended_reason = null where id = p_user;
  update auth.users set banned_until = null where id = p_user;
end $$;

create function public.admin_sign_out_everywhere(p_user uuid, p_reason text)
returns int language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := public.admin_actor(array['support']);
  n int;
begin
  perform public.admin_log(v_actor, 'user.signed_out_everywhere', p_user, null, p_reason);
  delete from auth.refresh_tokens where user_id = p_user::text;
  delete from auth.sessions where user_id = p_user;
  get diagnostics n = row_count;
  return n;
end $$;

-- Free or extra time on a plan (goodwill, partnerships). Extends any time
-- already granted/paid on that plan; never auto-renews.
create function public.admin_grant_plan(p_circle uuid, p_plan text, p_days int, p_reason text)
returns timestamptz language plpgsql security definer set search_path = '' as $$
declare
  v_actor  text := public.admin_actor(array['support']);
  v_circle public.circles;
  v_plan   public.plans;
  v_from   timestamptz;
  v_end    timestamptz;
begin
  select * into v_circle from public.circles where id = p_circle;
  if v_circle.id is null then raise exception 'circle not found' using errcode = 'P0002'; end if;
  select * into v_plan from public.plans where code = p_plan and is_active and code <> 'free';
  if v_plan.id is null then raise exception 'unknown plan' using errcode = 'P0001', hint = 'unknown_plan'; end if;
  if p_days is null or p_days < 1 or p_days > 366 then
    raise exception 'days must be 1–366' using errcode = 'P0001', hint = 'bad_days';
  end if;
  if not public.plan_fits_circle(p_plan, v_circle.type) then
    raise exception 'plan does not fit this circle' using errcode = 'P0001', hint = 'wrong_circle';
  end if;
  select greatest(now(), coalesce(max(coalesce(s.current_period_end, s.trial_end)), now())) into v_from
    from public.subscriptions s
   where s.circle_id = p_circle and s.plan_id = v_plan.id and public.subscription_entitles(s);
  v_end := v_from + make_interval(days => p_days);
  perform public.admin_log(v_actor, 'plan.granted', null, p_circle, p_reason,
                           jsonb_build_object('plan', p_plan, 'days', p_days, 'until', v_end));
  insert into public.subscriptions (circle_id, plan_id, provider, status, current_period_end,
                                    external_ref, cancel_at_period_end)
  values (p_circle, v_plan.id, 'manual', 'active', v_end, 'grant:' || gen_random_uuid(), true);
  insert into public.billing_events (circle_id, provider, event_id, type, plan_code, amount_inr)
  values (p_circle, 'manual', 'grant:' || gen_random_uuid(), 'grant', p_plan, 0);
  return v_end;
end $$;

create function public.admin_cancel_deletion(p_user uuid, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_actor text := public.admin_actor(array['support']);
begin
  if not exists (select 1 from public.account_deletions where user_id = p_user) then
    raise exception 'no deletion pending' using errcode = 'P0001', hint = 'none_pending';
  end if;
  perform public.admin_log(v_actor, 'deletion.cancelled', p_user, null, p_reason);
  delete from public.account_deletions where user_id = p_user;
end $$;

-- Immediate, irreversible deletion (e.g. a verified request from the web
-- form). Super-admins only.
create function public.admin_delete_now(p_user uuid, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_actor text := public.admin_actor(array[]::text[]);
begin
  if exists (select 1 from public.admins where user_id = p_user) then
    raise exception 'remove admin rights first' using errcode = 'P0001', hint = 'is_admin';
  end if;
  if not exists (select 1 from auth.users where id = p_user) then
    raise exception 'user not found' using errcode = 'P0002';
  end if;
  perform public.admin_log(v_actor, 'user.deleted', p_user, null, p_reason);
  delete from auth.users where id = p_user;  -- cascades to all their data
end $$;

create function public.admin_create_promo(p_code text, p_plan text, p_days int, p_max int,
                                          p_expires timestamptz, p_note text, p_reason text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := public.admin_actor(array['support']);
  v_code  text := upper(trim(p_code));
  v_plan  uuid;
begin
  if v_code !~ '^[A-Z0-9]{4,20}$' then
    raise exception 'code must be 4–20 letters/digits' using errcode = 'P0001', hint = 'bad_code';
  end if;
  select id into v_plan from public.plans where code = p_plan and code <> 'free';
  if v_plan is null then raise exception 'unknown plan' using errcode = 'P0001', hint = 'unknown_plan'; end if;
  if p_days is null or p_days < 1 or p_days > 366 then
    raise exception 'days must be 1–366' using errcode = 'P0001', hint = 'bad_days';
  end if;
  perform public.admin_log(v_actor, 'promo.created', null, null, p_reason,
                           jsonb_build_object('code', v_code, 'plan', p_plan, 'days', p_days, 'max', p_max));
  insert into public.promo_codes (code, plan_id, days, max_redemptions, expires_at, note)
  values (v_code, v_plan, p_days, p_max, p_expires, p_note);
  return v_code;
end $$;

create function public.admin_disable_promo(p_code text, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_actor text := public.admin_actor(array['support']);
begin
  if not exists (select 1 from public.promo_codes where code = upper(trim(p_code)) and is_active) then
    raise exception 'no active code' using errcode = 'P0001', hint = 'not_found';
  end if;
  perform public.admin_log(v_actor, 'promo.disabled', null, null, p_reason,
                           jsonb_build_object('code', upper(trim(p_code))));
  update public.promo_codes set is_active = false where code = upper(trim(p_code));
end $$;

-- Grant / change / remove admin rights (null role = remove). Super only.
create function public.admin_set_role(p_user uuid, p_role text, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_actor text := public.admin_actor(array[]::text[]);
begin
  if p_role is not null and p_role not in ('super', 'support', 'finance') then
    raise exception 'unknown role' using errcode = 'P0001', hint = 'bad_role';
  end if;
  if not exists (select 1 from public.users where id = p_user) then
    raise exception 'user not found' using errcode = 'P0002';
  end if;
  if coalesce(p_role, '') <> 'super'
     and exists (select 1 from public.admins where user_id = p_user and role = 'super')
     and (select count(*) from public.admins where role = 'super') = 1 then
    raise exception 'cannot remove the last super-admin' using errcode = 'P0001', hint = 'last_super';
  end if;
  perform public.admin_log(v_actor, 'admin.role_set', p_user, null, p_reason,
                           jsonb_build_object('role', p_role));
  if p_role is null then
    delete from public.admins where user_id = p_user;
  else
    insert into public.admins (user_id, role) values (p_user, p_role)
    on conflict (user_id) do update set role = excluded.role;
  end if;
end $$;

-- ===================================================== renewal notices
-- One row per (circle, recipient, period end, step, channel): sent once.
create table public.renewal_notices (
  id         uuid primary key default gen_random_uuid(),
  circle_id  uuid not null references public.circles (id) on delete cascade,
  user_id    uuid not null references public.users (id) on delete cascade,
  ends_at    timestamptz not null,
  step       text not null check (step in ('d7', 'd3', 'd1', 'd0', 'p3', 'p7', 'courtesy', 'payment_issue')),
  channel    text not null check (channel in ('whatsapp', 'email')),
  plan_code  text not null,
  status     text not null default 'claimed' check (status in ('claimed', 'sent', 'logged', 'failed')),
  error      text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (circle_id, user_id, ends_at, step, channel)
);
alter table public.renewal_notices enable row level security;
create policy renewal_notices_select on public.renewal_notices for select to authenticated
  using (user_id = (select auth.uid()));
create policy not_suspended on public.renewal_notices as restrictive for all to authenticated
  using ((select not public.is_suspended())) with check ((select not public.is_suspended()));

-- Per circle: latest paid-until, its plan, whether it renews by itself.
-- Considers subscriptions that are live or ended within the last 8 days.
-- Owner rights (not invoker): read by definer functions and report views;
-- clients can't select it.
create view public.circle_paid_until as
with recent as (
  select s.*, coalesce(s.current_period_end, s.trial_end) as ends
    from public.subscriptions s
   where coalesce(s.current_period_end, s.trial_end) > now() - interval '8 days'
)
select distinct on (r.circle_id)
       r.circle_id, r.ends as ends_at, p.code as plan_code, r.provider, r.status,
       (r.provider in ('revenuecat', 'razorpay') and not r.cancel_at_period_end
          and r.status in ('active', 'trialing', 'past_due')) as auto_renews
  from recent r join public.plans p on p.id = r.plan_id
 order by r.circle_id, r.ends desc;
revoke all on public.circle_paid_until from anon, authenticated;

-- Which step applies at p_now (daily run at 10:00 IST: windows are 1 day).
create function public.renewal_step(p_ends timestamptz, p_auto boolean, p_status text, p_now timestamptz)
returns text language sql immutable as $$
  select case
    when p_auto and p_status = 'past_due' then 'payment_issue'
    when p_auto then case when p_ends - p_now > interval '2 days' and p_ends - p_now <= interval '3 days'
                          then 'courtesy' end
    when p_ends - p_now > interval '6 days' and p_ends - p_now <= interval '7 days' then 'd7'
    when p_ends - p_now > interval '2 days' and p_ends - p_now <= interval '3 days' then 'd3'
    when p_ends - p_now > interval '0'      and p_ends - p_now <= interval '1 day'  then 'd1'
    when p_now - p_ends >= interval '0'     and p_now - p_ends < interval '1 day'   then 'd0'
    when p_now - p_ends >= interval '3 days' and p_now - p_ends < interval '4 days' then 'p3'
    when p_now - p_ends >= interval '7 days' and p_now - p_ends < interval '8 days' then 'p7'
  end;
$$;

-- Claims due notices for WhatsApp (opted-in) and email. Owners get every
-- step; members only "ended" (d0). Already-sent steps are skipped.
create function public.claim_renewal_notices(p_now timestamptz default now(), p_limit int default 500)
returns table (notice_id uuid, channel text, step text, user_id uuid, is_owner boolean,
               phone text, email text, plan_code text, plan_name text, circle_name text,
               ends_at timestamptz, timezone text)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  return query
  with c as (
    select pu.circle_id, pu.ends_at, pu.plan_code, pu.auto_renews,
           public.renewal_step(pu.ends_at, pu.auto_renews, pu.status::text, p_now) as step
      from public.circle_paid_until pu
     where pu.plan_code <> 'free'
  ), due as (
    select c.*, m.user_id, (m.role = 'owner') as is_owner
      from c
      join public.memberships m on m.circle_id = c.circle_id and m.status = 'active' and m.deleted_at is null
     where c.step is not null and (m.role = 'owner' or c.step = 'd0')
  ), targets as (
    select d.*, 'whatsapp'::text as ch, o.phone_e164 as phone, null::text as email
      from due d join public.whatsapp_optins o on o.user_id = d.user_id and o.enabled
    union all
    select d.*, 'email', null, u.email
      from due d join public.users u on u.id = d.user_id
     where u.email is not null and u.suspended_at is null
  ), ins as (
    insert into public.renewal_notices (circle_id, user_id, ends_at, step, channel, plan_code)
    select t.circle_id, t.user_id, t.ends_at, t.step, t.ch, t.plan_code from targets t
     limit p_limit
    on conflict do nothing
    returning id, renewal_notices.circle_id, renewal_notices.user_id, renewal_notices.step,
              renewal_notices.channel, renewal_notices.ends_at
  )
  select ins.id, ins.channel, ins.step, ins.user_id, t.is_owner, t.phone, t.email,
         t.plan_code, p.name, ci.name, ins.ends_at, coalesce(u.timezone, 'Asia/Kolkata')
    from ins
    join targets t on t.circle_id = ins.circle_id and t.user_id = ins.user_id
                  and t.step = ins.step and t.ch = ins.channel
    join public.plans p on p.code = t.plan_code
    join public.circles ci on ci.id = ins.circle_id
    join public.users u on u.id = ins.user_id;
end $$;

create function public.record_renewal_notice(p_id uuid, p_status text, p_error text)
returns void language sql security definer set search_path = '' as $$
  update public.renewal_notices set status = p_status, error = p_error, updated_at = now() where id = p_id;
$$;

create function public.kick_renewal_dispatch()
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_url text; v_secret text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'aria_functions_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'aria_cron_secret';
  if v_url is null or v_secret is null then return null; end if;
  return net.http_post(
    url := v_url || '/renewal-dispatch',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_secret),
    body := '{}'::jsonb);
end $$;
-- Daily at 10:00 IST (04:30 UTC): day-wide windows, nobody woken at night.
select cron.schedule('aria-renewal-dispatch', '30 4 * * *', 'select public.kick_renewal_dispatch()');

-- Premium ends within 5 minutes of the paid-until time (was 15).
select cron.unschedule('aria-expire-subscriptions');
select cron.schedule('aria-expire-subscriptions', '*/5 * * * *', 'select public.expire_subscriptions()');

-- The app's billing view gains renewal info and the recently lapsed plan.
drop function public.circle_billing(uuid);
create function public.circle_billing(p_circle uuid)
returns table (plan_code text, status public.subscription_status, provider text,
               period text, current_period_end timestamptz, trial_end timestamptz,
               cancel_at_period_end boolean, trial_used boolean, seats_used int, max_seats int,
               auto_renews boolean, lapsed_plan_code text, lapsed_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select p.code,
         s.status, s.provider, s.period, s.current_period_end, s.trial_end,
         coalesce(s.cancel_at_period_end, false),
         exists (select 1 from public.subscriptions t where t.circle_id = c.id and t.trial_end is not null),
         (select count(*)::int from public.memberships m where m.circle_id = c.id and m.status = 'active'),
         p.max_seats,
         coalesce(s.provider in ('revenuecat', 'razorpay') and not s.cancel_at_period_end
                  and s.status in ('active', 'trialing', 'past_due'), false),
         case when p.code = 'free' then lp.code end,
         case when p.code = 'free' then l.ends end
    from public.circles c
    join public.plans p on p.id = c.plan_id
    left join lateral (
      select * from public.subscriptions s
       where s.circle_id = c.id and public.subscription_entitles(s)
       order by coalesce(s.current_period_end, s.trial_end) desc limit 1) s on true
    left join lateral (
      select x.plan_id, coalesce(x.current_period_end, x.trial_end) as ends
        from public.subscriptions x
       where x.circle_id = c.id
         and coalesce(x.current_period_end, x.trial_end) between now() - interval '30 days' and now()
       order by coalesce(x.current_period_end, x.trial_end) desc limit 1) l on true
    left join public.plans lp on lp.id = l.plan_id
   where c.id = p_circle and public.is_circle_member(c.id);
$$;

-- ============================================================= reports
-- Read-only, metadata only (no reminder/note/list/place text). For the
-- support_readonly login and the future admin panel.
create schema reports;
revoke all on schema reports from public, anon, authenticated;

create view reports.users as
select u.id, u.name, u.phone, u.email, u.locale, u.created_at, u.last_seen_at,
       u.suspended_at, u.suspended_reason,
       (select max(p.sort) from public.memberships m join public.circles c on c.id = m.circle_id
          join public.plans p on p.id = c.plan_id
         where m.user_id = u.id and m.status = 'active') as best_plan_rank,
       (select count(*) from public.memberships m where m.user_id = u.id and m.status = 'active') as circles,
       (select count(*) from public.reminders r where r.created_by = u.id and r.deleted_at is null) as reminders,
       (select purge_after from public.account_deletions d where d.user_id = u.id) as deletion_after,
       (select role from public.admins a where a.user_id = u.id) as admin_role
  from public.users u;

create view reports.activity_daily as
with days as (select generate_series(current_date - 89, current_date, interval '1 day')::date as day),
acts as (
  select created_by as user_id, created_at::date as day from public.reminders
  union all select user_id, at::date from public.reminder_events
)
select d.day,
       (select count(*) from public.users u where u.created_at::date = d.day) as signups,
       (select count(distinct a.user_id) from acts a where a.day = d.day) as active_users,
       (select count(*) from public.reminders r where r.created_at::date = d.day) as reminders_created,
       (select count(*) from public.reminder_events e where e.at::date = d.day and e.type = 'done') as reminders_done,
       (select count(*) from public.reminder_events e where e.at::date = d.day and e.type = 'missed') as reminders_missed
  from days d order by d.day desc;

create view reports.circle_tenure as
select c.id as circle_id, c.name as circle_name, c.type, c.owner_id, p.code as current_plan,
       (select min(s.created_at) from public.subscriptions s
         where s.circle_id = c.id and s.provider <> 'manual') as first_paid_at,
       pu.ends_at as paid_until, pu.provider, pu.auto_renews,
       (select count(*) from public.billing_events b where b.circle_id = c.id and b.type in ('purchase', 'renewal')) as payments,
       (select count(*) from public.billing_events b where b.circle_id = c.id and b.type = 'renewal') as renewals,
       (select coalesce(sum(b.amount_inr), 0) from public.billing_events b where b.circle_id = c.id) as total_paid_inr,
       (select count(*) from public.memberships m where m.circle_id = c.id and m.status = 'active') as members
  from public.circles c
  join public.plans p on p.id = c.plan_id
  left join public.circle_paid_until pu on pu.circle_id = c.id;

create view reports.expiring as
select t.*, ceil(extract(epoch from (t.paid_until - now())) / 86400)::int as days_left
  from reports.circle_tenure t
 where t.paid_until between now() and now() + interval '30 days'
 order by t.paid_until;

create view reports.lapsed as
select c.id as circle_id, c.name as circle_name, c.owner_id, x.plan_code as lapsed_plan, x.ended_at,
       (select coalesce(sum(b.amount_inr), 0) from public.billing_events b where b.circle_id = c.id) as total_paid_inr
  from public.circles c
  join public.plans cp on cp.id = c.plan_id and cp.code = 'free'
  join lateral (
    select p.code as plan_code, coalesce(s.current_period_end, s.trial_end) as ended_at
      from public.subscriptions s join public.plans p on p.id = s.plan_id
     where s.circle_id = c.id
     order by coalesce(s.current_period_end, s.trial_end) desc limit 1) x on true
 where x.ended_at between now() - interval '60 days' and now()
 order by x.ended_at desc;

create view reports.subscriptions_overview as
select p.code as plan, s.provider, s.status, count(*) as circles,
       count(*) filter (where s.trial_end is not null) as trials
  from public.subscriptions s join public.plans p on p.id = s.plan_id
 where public.subscription_entitles(s)
 group by 1, 2, 3 order by 1, 2, 3;

create view reports.revenue_monthly as
select date_trunc('month', b.occurred_at)::date as month, b.plan_code, b.provider,
       count(*) filter (where b.type in ('purchase', 'renewal')) as payments,
       coalesce(sum(b.amount_inr), 0) as gross_inr
  from public.billing_events b
 group by 1, 2, 3 order by 1 desc, 2, 3;

create view reports.renewal_rate_monthly as
select date_trunc('month', b.occurred_at)::date as month,
       count(*) filter (where b.type = 'renewal') as renewed,
       count(*) filter (where b.type = 'expired') as ended,
       round(100.0 * count(*) filter (where b.type = 'renewal')
             / nullif(count(*) filter (where b.type in ('renewal', 'expired')), 0), 1) as renewal_rate_pct
  from public.billing_events b
 group by 1 order by 1 desc;

create view reports.trial_conversion as
select date_trunc('month', t.occurred_at)::date as month, count(*) as trials,
       count(*) filter (where exists (
         select 1 from public.billing_events b
          where b.circle_id = t.circle_id and b.type = 'purchase'
            and b.occurred_at between t.occurred_at and t.occurred_at + interval '30 days')) as converted
  from public.billing_events t where t.type = 'trial_started'
 group by 1 order by 1 desc;

create view reports.messaging_daily as
select created_at::date as day, 'whatsapp_reminder' as kind, status, count(*) as messages
  from public.whatsapp_outbox group by 1, 2, 3
union all
select created_at::date, 'renewal_' || channel, status, count(*)
  from public.renewal_notices group by 1, 2, 3
order by 1 desc, 2, 3;

create view reports.admin_activity as
select a.at, a.actor, a.action, a.target_user, a.target_circle, a.reason, a.details
  from public.admin_actions a order by a.at desc;

-- Read-only database login for support / finance. Ops sets a password:
--   alter role support_readonly with login password '…';
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'support_readonly') then
    create role support_readonly nologin;
  end if;
end $$;
alter role support_readonly set default_transaction_read_only = on;
alter role support_readonly set statement_timeout = '15s';
grant usage on schema reports to support_readonly, service_role;
grant select on all tables in schema reports to support_readonly, service_role;
alter default privileges in schema reports grant select on tables to support_readonly, service_role;

-- ============================================================== grants
revoke execute on function
  public.admin_actor(text[]), public.admin_log(text, text, uuid, uuid, text, jsonb),
  public.admin_suspend_user(uuid, text), public.admin_unsuspend_user(uuid, text),
  public.admin_sign_out_everywhere(uuid, text), public.admin_grant_plan(uuid, text, int, text),
  public.admin_cancel_deletion(uuid, text), public.admin_delete_now(uuid, text),
  public.admin_create_promo(text, text, int, int, timestamptz, text, text),
  public.admin_disable_promo(text, text), public.admin_set_role(uuid, text, text),
  public.claim_renewal_notices(timestamptz, int), public.record_renewal_notice(uuid, text, text),
  public.kick_renewal_dispatch(), public.is_suspended(),
  public.touch_last_seen(), public.account_status(), public.circle_billing(uuid)
  from anon, public;
-- Admin functions check the caller's admin role themselves.
grant execute on function
  public.admin_suspend_user(uuid, text), public.admin_unsuspend_user(uuid, text),
  public.admin_sign_out_everywhere(uuid, text), public.admin_grant_plan(uuid, text, int, text),
  public.admin_cancel_deletion(uuid, text), public.admin_delete_now(uuid, text),
  public.admin_create_promo(text, text, int, int, timestamptz, text, text),
  public.admin_disable_promo(text, text), public.admin_set_role(uuid, text, text),
  public.touch_last_seen(), public.account_status(), public.circle_billing(uuid), public.is_suspended()
  to authenticated;
revoke execute on function public.claim_renewal_notices(timestamptz, int),
                           public.record_renewal_notice(uuid, text, text)
  from authenticated;
grant execute on function public.claim_renewal_notices(timestamptz, int),
                          public.record_renewal_notice(uuid, text, text) to service_role;
